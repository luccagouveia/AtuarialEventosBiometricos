# ⚡ Guia de Engenharia de Performance e Tuning (SQL Server)

**Projeto:** AtuarialEventosBiometricos (RPPS)  
**Benchmark de Otimização:** Redução do tempo médio de execução de **~45 minutos para ~1 minuto** (~97,7% de ganho de latência)  
**Objetivo:** Documentar as decisões arquiteturais de baixo nível no *Query Optimizer* do SQL Server que eliminaram gargalos de I/O, estouros de `TempDB` (*Spills*) e falhas de transporte de rede.

---

## 1. Diagnóstico do Gargalo Original (Arquitetura Monolítica)

Nas versões iniciais de extração previdenciária, consultas monolíticas cruzavam diretamente múltiplas views corporativas e cubos históricos sem materialização intermediária. Esse modelo gerava quatro problemas críticos no plano de execução:

1. **Varredura Completa em Tabelas Massivas (*Full Scan*):** O cruzamento direto com o histórico mensal da folha (`fato_folha_cabecalho`, com **+51 milhões de registros**) forçava o SQL Server a ler todo o histórico antes de aplicar os filtros de elegibilidade RPPS.
2. **Estimativas de Cardinalidade Imprecisas (*Cardinality Estimation Skew*):** Views aninhadas com filtros textuais (`FORMAVAC`, `TIPOAPOS`) faziam o otimizador subestimar o volume de linhas, alocando *Memory Grants* insuficientes e provocando **TempDB Spills** (escrita forçada em disco durante operações de *Hash Match* e *Sort*).
3. **Contenção de Bloqueios (*Lock Escalation*):** Leituras longas sob o nível de isolamento padrão (`READ COMMITTED`) adquiriam *Shared Locks* prolongados, competindo com rotinas operacionais.
4. **Quebra de *SARGability*:** Conversões de data (`CONVERT`) e concatenações de chaves aplicadas dentro das cláusulas `JOIN` e `WHERE` impediam o uso de índices existentes.

---

## 2. Pilares de Otimização Aplicados

### 2.1 Multi-Staging Tables (`#TMP`) com Índices Clusterizados (`B-Tree`)
Em vez de encadear subqueries profundas sobre milhões de registros, a arquitetura materializa primeiro o **Motor Central (Driver Populacional)** contendo apenas as chaves numéricas primárias (`NUMFUNC`, `NUMVINC`) — reduzindo o universo de milhões de linhas para **~113.922 chaves únicas** no layout de ativos, por exemplo.

Logo após a criação de cada `#TMP`, um índice clusterizado é construído explicitamente:
```sql
CREATE CLUSTERED INDEX IX_TMP_ATIVOS_CHAVE ON #TMP_ATIVOS (NUMFUNC, NUMVINC);
```
**Impacto no Plano de Execução:**
* Transforma a tabela temporária de uma estrutura desordenada (*Heap*) em uma árvore balanceada (**B-Tree**) fisicamente ordenada pela chave de junção.
* Permite que o *Query Optimizer* substitua junções custosas (*Hash Join* com alto consumo de memória) por **Merge Joins** (quando ambos os lados estão ordenados) ou **Nested Loops com Index Seek** instantâneo.
* Atualiza as estatísticas da tabela temporária no momento da criação do índice, garantindo *Memory Grants* precisos.

---

### 2.2 Predication Pushdown & Semi-Joins (`WHERE EXISTS`)
Para evitar que o SQL Server processe registros de segurados fora do escopo (como vínculos RGPS ou comissionados), aplicamos *Predication Pushdown* em todos os módulos secundários utilizando `WHERE EXISTS`:

```sql
WITH CTE_ULTIMA_COMPETENCIA AS (
    SELECT 
        h.NUMFUNC,
        h.NUMVINC,
        MAX(h.MES_ANO) AS ULTIMO_MES
    FROM rpps_dw.fato_folha_cabecalho h
    WHERE EXISTS (
        SELECT 1 FROM #TMP_ATIVOS i 
        WHERE i.NUMFUNC = h.NUMFUNC AND i.NUMVINC = h.NUMVINC
    )
    GROUP BY h.NUMFUNC, h.NUMVINC
)
```
**Impacto no Plano de Execução:**
* O operador **Left Semi Join** interrompe a busca na tabela interna assim que a primeira correspondência é encontrada.
* Reduz drasticamente as **Leituras Lógicas (*Logical Reads*)** e o I/O de disco sobre os +51 milhões de registros da fato financeira/funcional.

---

### 2.3 Late Materialization e Preservação de *SARGability*
Todas as transformações cosméticas e de tipagem — como concatenação de matrículas (`CAST(NUMFUNC AS VARCHAR) + '-' + CAST(NUMVINC AS VARCHAR)`), formatação de datas (`CONVERT(VARCHAR(10), ..., 103)`) e traduções de domínio (`CASE WHEN`) — foram empurradas estritamente para o **`SELECT` do módulo final**.

* **Durante os `JOINs`:** As chaves trafegam exclusivamente em seus tipos numéricos nativos (`INT` / `BIGINT`), preservando a eficiência máxima da CPU e dos índices.
* **Saneamento Seguro:** O uso de `TRY_CONVERT(..., 103)` isola anomalias de datas em strings legadas sem comprometer o plano de execução.

---

### 2.4 Estratégia Híbrida: `#Temp Tables` vs. `CTEs`
O projeto adota critérios claros de engenharia para escolher entre materialização física (`#TMP`) e pipelines declarativos (`CTE`):
* **Uso de `#TMP` Indexada (`01_ativos`, `01_aposentados`, `02_corte`, `03_pensionistas_atuais`):** Aplicado quando a população filtrada cruza com múltiplas tabelas de alta volumetria (+100k a +51M linhas) ou quando a mesma base precisa ser reutilizada em múltiplos módulos (ex.: cálculo de ingresso `DT_ING_ENTE` + histórico de cargos + dados cadastrais).
* **Uso de `CTEs` Encadeadas (`04_pensionistas_vacancia`, `04_pensionistas_historico_obitos`):** Aplicado quando o recorte temporal (`>= '2015-01-01'`) e o filtro de órgão (`EMP_CODIGO = 6`) já reduzem o driver inicial para uma fração enxuta de registros, permitindo execução em fluxo único sem overhead de alocação em disco.

---

## 3. Comparativo de Performance (Antes vs. Depois)

| Métrica de Engenharia | Arquitetura Monolítica (Antes) | Arquitetura Modular Otimizada (Depois) |
| :--- | :--- | :--- |
| **Tempo Total de Execução** | ~45 minutos (com risco de timeout) | **~1 minuto** |
| **Estratégia de Junção Predominante** | *Hash Match* / *Nested Loops* com *Scan* | **Merge Join** / *Index Seek* via B-Tree |
| **Leituras Lógicas (*Logical Reads*)** | Extremamente elevadas (varredura de +51M linhas) | **Reduzidas em >95%** (*Predication Pushdown*) |
| **Uso de `TempDB`** | Descontrolado (*Hash/Sort Spills* em disco) | **Controlado** (`#TMP` enxutas com `DROP` explícito) |
| **Bloqueios / Concorrência** | Aquisição de *Shared Locks* prolongados | **Zero bloqueios** (`READ UNCOMMITTED` + `NOCOUNT ON`) |
| **Estabilidade de Rede** | Sujeita a queda de conexão (`Erro 10053`) | **Estável** (fluxo contínuo e baixa latência) |
