# 📊 Layout Eventos Biométricos (Atuarial) — SQL Server Avançado & Performance Tuning (RPPS)

> Solução analítica em **Microsoft SQL Server (T-SQL)** para extração, saneamento cadastral e consolidação longitudinal de informações biométricas e previdenciárias destinadas a **Estudos de Aderência Atuarial**, **Censo Previdenciário** e **Avaliações Atuariais** de RPPS, em conformidade com a **Portaria MTP nº 1.467/2022**.

---

# 1. Visão Geral e Contexto de Negócio

Desenvolvido para atender às especificações da consultoria atuarial (**FIA-USP**) e à **Divisão de Gestão da Base Cadastral (DGBC)**, o projeto transforma bases operacionais legadas em datasets padronizados (`1:1`) e auditáveis. Subscreve o Censo Previdenciário, Testes de Aderência, Avaliações Anuais e a consolidação de coortes históricas (`01/01/2015` a `31/05/2026`) abrangendo ativos, aposentados, pensionistas, desligamentos e dependentes.

---

# 2. Problema de Negócio

Sistemas previdenciários legados apresentam desafios como:
- Múltiplas fontes fragmentadas e regras de movimentação dispersas (`49` variações de vacância);
- Datas armazenadas em formato textual (`VARCHAR`) com espaços irregulares;
- Múltiplos vínculos por indivíduo (`1:N`) e alto volume de dados (ex.: cabeçalhos de folha com **+51 milhões de registros**);
- Dependências complexas entre instituidores e pensionistas.

---

# 3. Metodologia (Ciclo 5D)

1. **Discovery:** Levantamento de requisitos, mapeamento de legados e enquadramento normativo.
2. **Development:** Modelagem em T-SQL, filtros de elegibilidade, regras de precedência biométrica e otimização.
3. **Deploy:** Validação de planos de execução, monitoramento de concorrência e controle do `TempDB`.
4. **Delivery:** Homologação cruzada de quantitativos e entrega dos layouts consolidados.
5. **Documentation:** Criação do dicionário de dados, linhagem (*Data Lineage*) e sanitização *LGPD by Design*.

---

# 4. Soluções e Layouts Homologados

Arquitetura modular dividida em 6 layouts especializados:

- **01 — Ativos Vigentes:** Servidores efetivos (`REGIMEPREV = 'RPPS'`) e último cargo.
- **01 — Aposentados Vigentes:** Aposentados não vacanciados (programados vs. invalidez).
- **02 — Coorte Histórica:** Desligamentos, exonerações e óbitos (`2015–2026`).
- **03 — Pensionistas Atuais:** Pensionistas vigentes com tradução de parentesco/condição.
- **04 — Pensionistas Vacância / Histórico Legado:** Benefícios encerrados ou óbitos desde 2015.

*(Consulte o repositório completo para acessar os scripts SQL e as especificações detalhadas de cada layout).*

---

# 5. Arquitetura (EFMP) & Regras de Negócio

Operada no padrão **Extract-Filter-Materialize-Project (EFMP)**, garante *Data Lineage* rastreável, separação de domínios, alta performance, idempotência e LGPD by Design. 

**Regras principais:**
- **RN001 (Elegibilidade):** Restringe ao RPPS e à janela temporal de `01/01/2015` a `31/05/2026`.
- **RN002 (Precedência Biométrica):** Higieniza motivos de vacância (`FORMAVAC`) em óbitos, desligamentos e aposentadorias, preservando datas cruzadas sem sobreposições indevidas.
- **RN003–RN006:** Garantem unicidade de pensionistas por beneficiário único, reconstrução da data de ingresso (`DTEXERC`), última carreira válida e classificação correta de dependentes.

---

# 6. Performance e Benchmark

A adoção de `READ UNCOMMITTED`, estruturas temporárias indexadas (`#TMP` com `CLUSTERED INDEX`), *Predication Pushdown* (`WHERE EXISTS`) e pré-agregações reduziu drasticamente o custo computacional:

| Indicador Técnico | Antes | Depois |
| :--- | :--- | :--- |
| **Tempo de Execução** | ~45 min | **~1 min** (~97,7% de ganho) |
| **Leituras Lógicas** | *Full Scans* pesados | **Reduzidas em >95%** (*Index Seeks*) |
| **Consumo de `TempDB`** | Spills em disco | **Controlado** (`#TMP` indexadas com `DROP`) |
| **Concorrência** | *Shared Locks* / *Deadlocks* | **Zero bloqueios** (`READ UNCOMMITTED`) |

---

# 7. Governança e LGPD (*Privacy by Design*)

Em conformidade com a Lei nº 13.709/2018, o projeto utiliza **zero dados reais** (sem CPFs, nomes ou bases exportadas em CSV/XLSX). Bancos e tabelas reais são abstraídos por aliases públicos sob o namespace `rpps_dw` (ex.: `fato_folha_cabecalho`, `tbl_historico_vinculos`, `dim_carreiras`).

---

# 8. Estrutura do Repositório

```text
AtuarialEventosBiometricos/
├── docs/
│   ├── engenharia-sql/   # Diretrizes T-SQL, performance e troubleshooting
│   └── governance/       # Layouts, Data Lineage, dicionário LGPD e Portaria MTP 1467
├── sql_queries/          # Scripts SQL modulares (ativos, aposentados, pensionistas, cortes)
├── .gitignore            # Proteção contra vazamento de arquivos de dados
└── README.md
```

---

# 9. Métricas, Competências e Roadmap

- **Volumetria:** +113 mil ativos em `1:1`, +51 milhões de registros de folha filtrados, +40 mil registros históricos auditados (2015–2026).
- **Stack:** T-SQL Avançado, Query Performance Tuning, Modelagem Analítica RPPS, Portaria MTP 1467/2022 e LGPD.
- **Próximos Passos:** Automação de extrações via Python, validação de schemas em CI/CD e monitoramento contínuo de novos códigos `FORMAVAC`.

> **Nota:** Solução homologada e adaptada para fins de portfólio técnico, com anonimização completa de entidades e credenciais.

© SQL Server Avançado, Performance Tuning & Governança Atuarial | Portfólio Técnico
