# ⚖️ Base Normativa e Conformidade Regulatória (Portaria MTP nº 1.467/2022)

**Normativo de Referência:** Portaria MTP nº 1.467, de 02 de junho de 2022 (atualizada até a Portaria MPS nº 2.582, de 26/12/2025)  
**Órgão Regulador:** Ministério do Trabalho e Previdência / Ministério da Previdência Social (SPREV)  
**Escopo no Projeto:** Fundamentação legal e atuarial para extração, saneamento e segregação da base cadastral e de eventos biométricos do RPPS.

---

## 1. Visão Geral e Objetivo Regulatório

A **Portaria MTP nº 1.467/2022** disciplina os parâmetros e diretrizes gerais para a organização e o funcionamento dos Regimes Próprios de Previdência Social (RPPS), regulamentando a Lei nº 9.717/1998 e a Emenda Constitucional nº 103/2019.

No contexto do projeto **AtuarialEventosBiometricos**, os layouts extraídos fornecem os insumos obrigatórios para:
* **Avaliação Atuarial Anual** (Capítulo IV, Seção I, Art. 26);
* **Relatório de Análise das Hipóteses Biométricas e Demográficas** (Capítulo IV, Seção VI, Arts. 35 e 36);
* **Auditoria e Consistência da Base Cadastral** (Capítulo IV, Seção VII, Art. 47).

---

## 2. Matriz de Rastreabilidade: Normativo x Regras SQL

A tabela abaixo conecta diretamente os artigos da Portaria MTP nº 1.467/2022 às regras implementadas nas queries da camada `sql_queries/`:

| Dispositivo Legal | Exigência Regulatória | Implementação Técnica no Projeto (`sql_queries/`) |
| :--- | :--- | :--- |
| **Art. 2º, Incisos III e IV & Art. 3º** | Segregação estrita entre segurados efetivos do RPPS e agentes exclusivamente comissionados/temporários (vinculados ao RGPS). | Filtro explícito `REGIMEPREV = 'RPPS'` e restrição aos códigos de órgãos estatutários (`EMP_CODIGO IN (1, 2, 8, 91)`), descartando vínculos RGPS. |
| **Art. 5º** | Qualificação dos dependentes em gozo de pensão por morte e dos aposentados como beneficiários do regime. | Isolamento da população de aposentados (`01_aposentados_vigentes.sql`) e de pensionistas (`EMP_CODIGO = 6` nos layouts `03` e `04`). |
| **Art. 6º** | Mapeamento das hipóteses de perda da condição de segurado ou beneficiário (morte, exoneração, demissão, cassação, implemento de idade ou condição). | Taxonomia completa de vacâncias em `02_serv_corte_historico.sql` (49 códigos classificados) e nos 16 motivos homologados de encerramento de pensão (`04_pensionistas_vacancia.sql`). |
| **Art. 28, Inciso I & Art. 58** | Separação das massas previdenciárias (Fundo em Repartição vs. Fundo em Capitalização / Segregação de Massa) para acompanhamento do passivo. | Atribuição explícita do identificador `CO_COMP_MASSA` em cada layout (`1` para Massa Civil/Ativos/Corte/Pensionistas e `2` para Aposentados específicos). |
| **Art. 30, Incisos I e II** | Distinção entre benefícios programáveis (aposentadorias programadas, financiadas em capitalização) e riscos não programáveis (invalidez/incapacidade e pensão por morte). | Segregação mutuamente exclusiva entre `DT_APOSENTADORIA_PROGRAMADA` e `DT_APOSENTADORIA_POR_INVALIDEZ` (prefixos `INV%`, `INC%` e `APOS_INVALIDEZ`). |
| **Art. 35, Inciso III (alíneas c, d, e, f)** | Comprovação da aderência das hipóteses de mortalidade, entrada em invalidez, composição familiar (dependentes), idade de ingresso e idade de aposentadoria. | Extração da coorte histórica desde `01/01/2015` (`02_serv_corte_historico.sql`), cálculo de `DT_ING_ENTE` (`MIN(DTEXERC)`), `DT_OBITO` e contagem individual de dependentes (`QTD_PENSIONISTAS`). |
| **Art. 36, Incisos I e II** | Segregação obrigatória por sexo para aplicação das tábuas de mortalidade (IBGE) e entrada em invalidez (Álvaro Vindas). | Padronização rigorosa dos atributos `CO_SEXO_SEGURADO` e `CO_SEXO_PENSIONISTA` (`'F' -> '1'`, `'M' -> '2'`). |
| **Art. 42** | Dimensionamento do grupo familiar e elegibilidade de dependentes para cálculo de pensão por morte. | Mapeamento detalhado de parentesco (`CO_TIPO_RELACAO` de `1` a `6`) e condição de invalidez (`CO_CONDICAO`: `'2'` para deficiente, `'1'` para válido). |
| **Art. 47, §§ 1º e 5º** | Disponibilização de base cadastral completa, atualizada, consistente e auditável à unidade gestora e à SPREV. | Garantia de granularidade `1:1` por vínculo/beneficiário, saneamento de strings legadas (`FORMAVAC_LIMPO`) e rastreabilidade completa via *Data Lineage*. |

---

## 3. Regras Críticas de Qualidade de Dados Derivadas da Portaria

Para atender ao **Art. 47, § 5º, inciso II** (análise de atualização, amplitude e consistência da base cadastral), o pipeline SQL aplica quatro travas de integridade:

1. **Unicidade por Beneficiário (Evitar Sub/Superdimensionamento Familiar — Art. 35, III, "d"):**
   * A contagem de pensionistas vinculados a um instituidor (`QTD_PENSIONISTAS`) utiliza `COUNT(DISTINCT NUM_PEN_FUNC)`, contabilizando indivíduos únicos e não a quantidade de cotas ou processos administrativos.
2. **Precedência Biométrica na Coorte Histórica (Art. 6º e Art. 36):**
   * Em desligamentos históricos (`02_serv_corte_historico.sql`), caso um servidor se aposente e venha a falecer posteriormente, ambas as datas (`DT_APOSENTADORIA_*` e `DT_OBITO`) são preservadas para permitir o cálculo correto das probabilidades de mortalidade de aposentados ($q_x$).
   * A data de exoneração (`DT_EXONERACAO`) é suprimida caso haja registro de óbito no mesmo vínculo, evitando dupla contagem de decrementos.
3. **Expurgo de Registros Administrativos Inválidos (Art. 47):**
   * Motivos de encerramento que não representam eventos biométricos ou demográficos reais (como `'NULO / INDEFERIDO'`, `'INCLUSAO INDEVIDA'` e `'EXON CONV ADMINISTR'`) são filtrados na camada de extração.
4. **Saneamento Temporal (Janela de Aderência):**
   * Os estudos de aderência biométrica e rotatividade (Art. 37, § 1º, II) utilizam janela histórica consolidada a partir de **`01/01/2015`** até a data-base cadastral de **`31/05/2026`**.
