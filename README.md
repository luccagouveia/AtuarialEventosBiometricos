# Layout Eventos Biométricos (Atuarial)

> Projeto de extração, tratamento e consolidação de informações biométricas e previdenciárias destinadas à composição da base cadastral utilizada em avaliações atuariais e estudos de aderência de RPPS
>
> **Status:** Homologado e em Produção
> **Stack Tecnológica:** Microsoft SQL Server, T-SQL, Data Engineering, Data Quality, Data Governance e Modelagem de Dados
> **Domínio de Negócio:** Previdência Pública (RPPS), Censo Previdenciário, Avaliação Atuarial, Aderência Cadastral e Eventos Biométricos
> **Arquitetura da Solução:** Processamento Modular Orientado a Regras de Negócio, Alta Performance, Governança de Dados, Auditabilidade e LGPD by Design

---

# Visão Geral

Este projeto foi desenvolvido para atender necessidades de:

- Censo Previdenciário;
- Teste de Aderência Atuarial;
- Estudos de Hipóteses Biométricas;
- Avaliações Atuariais;
- Consistência Cadastral;
- Construção de Bases Históricas para projeções atuariais.

O objetivo principal consiste em transformar bases operacionais complexas em datasets atuariais padronizados, auditáveis e aderentes às regulamentações aplicáveis aos RPPS.

A solução consolida informações referentes a:

- Segurados ativos;
- Aposentados;
- Pensionistas;
- Beneficiários cessados;
- Óbitos;
- Exonerações;
- Aposentadorias;
- Invalidez;
- Dependentes;
- Históricos funcionais.

---

# Problema de Negócio

Processos atuariais exigem bases históricas e cadastrais extremamente consistentes.

Entretanto, normalmente os sistemas previdenciários apresentam:

- Múltiplas fontes de dados;
- Regras dispersas;
- Registros históricos incompletos;
- Mudanças de estrutura funcional;
- Eventos armazenados em formatos inconsistentes;
- Alto volume de dados;
- Dependências entre segurados e beneficiários.

Isso dificulta:

- Avaliações atuariais;
- Estudos de aderência;
- Auditorias;
- Consolidações históricas;
- Atendimento a órgãos fiscalizadores.

---

# Solução Desenvolvida

Foi construída uma arquitetura de extração composta por múltiplos layouts especializados.

Cada layout possui finalidade específica e regras próprias de negócio.

## Layouts Implementados

| Layout | Objetivo |
|----------|----------|
| `01-layout-ativos` | Base de segurados ativos |
| `01-layout-aposentados` | Base de aposentados vigentes |
| `02-layout-corte` | Coorte histórica de desligamentos |
| `03-layout-pensionistas-atuais` | Pensionistas vigentes |
| `04-layout-pensionistas-vacancia` | Pensionistas com benefício encerrado |
| `04-layout-pensionistas-historico` | Histórico de desligamentos e eventos biométricos |

---

# Arquitetura de Dados

## Visão Conceitual

```text
 ┌────────────────────────┐
 │ Sistemas Corporativos  │
 └────────────┬───────────┘
              │
              ▼
 ┌────────────────────────┐
 │ Extração SQL Modular   │
 └────────────┬───────────┘
              │
              ▼
 ┌────────────────────────┐
 │ Camada de Saneamento   │
 └────────────┬───────────┘
              │
              ▼
 ┌────────────────────────┐
 │ Regras de Negócio      │
 └────────────┬───────────┘
              │
              ▼
 ┌────────────────────────┐
 │ Consolidação Atuarial  │
 └────────────┬───────────┘
              │
              ▼
 ┌────────────────────────┐
 │ Datasets de Entrega    │
 └────────────────────────┘
```

---

# Arquitetura Técnica

A arquitetura foi construída seguindo princípios de:

- Data Lineage
- Separation of Concerns
- Performance First
- Reprodutibilidade
- Auditabilidade
- Governança de Dados

## Componentes

### Tabela Fato Principal

Representa os vínculos previdenciários.

Alias de documentação:

```text
tbl_historico_vinculos
```

Responsável por:

- ingresso;
- desligamento;
- aposentadoria;
- condição funcional;
- situação previdenciária.

---

### Cadastro Biográfico

Alias:

```text
tbl_cadastro_pessoas
```

Responsável por:

- sexo;
- data de nascimento;
- identificação cadastral.

---

### Controle de Encerramentos

Alias:

```text
tbl_eventos_encerramento
```

Responsável por:

- óbitos;
- exonerações;
- vacâncias;
- aposentadorias.

---

### Histórico de Beneficiários

Alias:

```text
tbl_beneficiarios_previdenciarios
```

Responsável por:

- dependentes;
- pensionistas;
- relação com instituidor.

---

### Histórico Financeiro

Alias:

```text
fato_financeira_previdenciaria
```

Responsável por:

- abono permanência;
- competências históricas;
- benefícios financeiros.

---

### Evolução Funcional

Alias:

```text
tbl_evolucao_funcional
```

Responsável por:

- cargos;
- carreiras;
- progressões;
- movimentação funcional.

---

# Regras de Negócio Principais

## RN001 — Elegibilidade Temporal

Considera:

- registros atuais;
- registros históricos;
- eventos ocorridos a partir da data de corte definida pelo estudo.

---

## RN002 — Classificação de Eventos

Os eventos são segregados entre:

- óbito;
- aposentadoria programada;
- aposentadoria por invalidez;
- exoneração;
- vacância.

Evita interpretação incorreta de um mesmo evento por múltiplas categorias.

---

## RN003 — Pensionistas

A quantidade de pensionistas é calculada por indivíduo beneficiário.

Não é calculada por benefício.

Isso evita subdimensionamento de dependentes vinculados ao mesmo instituidor.

---

## RN004 — Data de Ingresso

A data considerada corresponde ao primeiro ingresso identificado na carreira pública.

A regra reconstrói toda a cronologia funcional do segurado.

---

## RN005 — Última Carreira

A carreira retornada representa:

- cargo atual dos ativos;
- último cargo ocupado para desligados;
- última posição funcional válida antes do evento biométrico.

---

## RN006 — Abono de Permanência

A identificação ocorre através da primeira ocorrência histórica do benefício.

Permitindo análises futuras de comportamento previdenciário.

---

# Técnicas de Engenharia Utilizadas

## Common Table Expressions (CTEs)

Utilizadas para:

- modularização;
- legibilidade;
- manutenção.

---

## Predication Pushdown

Aplicado para:

- reduzir varreduras;
- limitar leitura precoce dos dados.

---

## EXISTS-Based Filtering

Substituição de junções custosas quando apenas existência era necessária.

Benefícios:

- menor I/O;
- menor uso de memória.

---

## Temporary Indexed Structures

Uso intensivo de:

```sql
#temp tables
```

com índices apropriados.

Resultado:

- redução de tempo de execução;
- estabilidade operacional.

---

## Conversões Seguras

Uso de:

```sql
TRY_CONVERT()
```

para:

- datas;
- numéricos;
- saneamento de dados legados.

---

## Window Functions

Utilizadas para:

- reconstrução histórica;
- identificação de último cargo;
- ordenação cronológica.

Exemplo:

```sql
ROW_NUMBER()
OVER(
PARTITION BY Segurado
ORDER BY DataEvento DESC
)
```

---

# Performance

## Situação Original

Consultas analíticas apresentavam:

- alto consumo de memória;
- leituras excessivas;
- tempos superiores a 45 minutos.

---

## Situação Final

Após otimização:

| Indicador | Antes | Depois |
|------------|--------|---------|
| Tempo execução | ~45 min | ~1 min |
| Leituras lógicas | Muito altas | Reduzidas |
| Consumo de TempDB | Elevado | Controlado |
| Escalabilidade | Limitada | Alta |

---

# Governança de Dados

O projeto segue práticas de:

## Data Quality

- validação de datas;
- tratamento de campos inválidos;
- remoção de duplicidades;
- consistência referencial.

---

## Data Lineage

Todo atributo possui rastreabilidade:

```text
Origem
 ↓
Transformação
 ↓
Regra Negócio
 ↓
Saída
```

---

## Auditabilidade

Cada layout possui:

- regras documentadas;
- critérios de inclusão;
- critérios de exclusão;
- justificativas atuariais.

---

# Segurança e LGPD

## Política de Anonimização

Por diretriz de segurança:

✅ Não são divulgados:

- bancos de dados reais;
- tabelas reais;
- views reais;
- colunas reais;
- entidades reais;
- servidores;
- conexões.

---

## Convenção de Aliases

| Ambiente Real | Alias Público |
|---------------|---------------|
| Banco Previdenciário | `rpps_dw` |
| Histórico de vínculos | `tbl_historico_vinculos` |
| Cadastro biográfico | `tbl_cadastro_pessoas` |
| Controle de eventos | `tbl_eventos_encerramento` |
| Histórico financeiro | `fato_financeira_previdenciaria` |
| Evolução funcional | `tbl_evolucao_funcional` |
| Beneficiários | `tbl_beneficiarios_previdenciarios` |
| Dimensão cargos | `dim_carreiras` |

---

# Estrutura do Repositório

```text
AtuarialEventosBiometricos/

├── README.md

├── docs/
│
├── arquitetura/
│   ├── data-lineage.md
│   ├── regras-negocio.md
│   ├── modelagem-conceitual.md
│
├── sql/
│
│   ├── 01-layout-ativos/
│   ├── 02-layout-aposentados/
│   ├── 03-layout-corte/
│   ├── 04-layout-pensionistas/
│
├── tests/
│
├── validation/
│
├── samples/
│
├── diagrams/
│
└── assets/
```

---

# Métricas do Projeto

## Volumetria

- Mais de 100 mil segurados processados.
- Mais de 40 mil registros históricos auditados.
- Múltiplos anos de histórico previdenciário.

---

## Complexidade

- Dados cadastrais;
- Dados funcionais;
- Eventos biométricos;
- Benefícios;
- Dependentes;
- Histórico financeiro.

---

# Competências Demonstradas

## Engenharia de Dados

- SQL Server
- T-SQL Avançado
- Data Modeling
- ETL
- Data Quality
- Performance Tuning

## Arquitetura

- Data Lineage
- Governança de Dados
- Modelagem Conceitual
- Modelagem Lógica

## Atuária

- Censo Previdenciário
- Teste de Aderência
- Hipóteses Biométricas
- Segregação de Massa
- Estudos Atuariais

## Governança

- LGPD
- Auditabilidade
- Reprodutibilidade
- Documentação Técnica

---

# Roadmap

## Próximas Evoluções

- Automatização via Python;
- Orquestração de pipelines;
- Validação automática de layouts;
- Testes de qualidade de dados;
- Migração para arquitetura Lakehouse;
- Modelagem em dbt;
- Integração CI/CD.

---

# Disclaimer

Este repositório possui caráter exclusivamente educacional e de demonstração técnica.

Todos os elementos que possam permitir identificação de:

- órgãos;
- entidades;
- pessoas;
- bases de dados;
- ambientes corporativos;

foram anonimizados e substituídos por aliases aderentes às melhores práticas de segurança da informação e proteção de dados.

Nenhum dado real, pessoal ou sigiloso é distribuído neste projeto.

---
© Engenharia de Dados Aplicada à Previdência Pública | Portfólio Técnico