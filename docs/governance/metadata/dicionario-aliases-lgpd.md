# 🔒 Dicionário de Aliases e Governança LGPD (*Privacy by Design*)

**Projeto:** AtuarialEventosBiometricos (RPPS)  
**Diretriz:** Conformidade com a Lei Geral de Proteção de Dados (Lei nº 13.709/2018) e Segurança da Informação  
**Objetivo:** Documentar a camada de abstração utilizada no repositório público para ocultar nomes de bancos corporativos, esquemas internos, views proprietárias e identificadores reais.

---

## 1. Política de Anonimização Estrutural

Para garantir a auditabilidade técnica do código T-SQL sem expor a topologia interna do ambiente de produção, este repositório aplica três regras rígidas de sanitização:

1. **Abstração de Banco e Esquema:** Todos os bancos de dados e esquemas internos foram unificados sob o namespace público `rpps_dw`.
2. **Aliases Semânticos de Objetos:** Views transacionais, cubos analíticos e tabelas legadas foram renomeados para entidades conceituais de mercado (`tbl_*`, `fato_*`, `dim_*`).
3. **Expurgo de Dados Pessoais e Chaves Reais:** Nenhuma matrícula funcional real, CPF, nome ou registro de carga em lote (*Batch Insert*) é versionado neste repositório. Exemplos ilustrativos utilizam sequências fictícias (`1000001`).

---

## 2. Catálogo de Entidades e Aliases Públicos

A tabela abaixo mapeia todas as entidades utilizadas nos scripts da pasta `sql_queries/`:

| Alias Público no Repositório | Tipo de Objeto | Domínio Funcional | Chaves de Junção Principais | Scripts Consumidores |
| :--- | :--- | :--- | :--- | :--- |
| `rpps_dw.tbl_historico_vinculos` | View / Tabela Fato | Driver principal de vínculos funcionais, ingresso, aposentadoria, vacância e regime previdenciário (`RPPS` / `EMP_CODIGO`). | `NUMFUNC`, `NUMVINC` | `01_ativos`, `01_aposentados`, `02_corte`, `03_pens_atuais`, `04_pens_vac` |
| `rpps_dw.tbl_detalhe_vacancias` | View Complementar | Detalhamento de datas exatas de desligamento e vacância (`DTVAC`) utilizadas no recorte histórico. | `NUMFUNC`, `NUMVINC` | `02_serv_corte_historico` |
| `rpps_dw.tbl_cadastro_pessoas` | View Cadastral | Dados biográficos e demográficos do segurado ou beneficiário (`SEXO`, `DTNASC`, `DEFICIENTE`). | `NUMERO` (`= NUMFUNC`) | `01_ativos`, `01_aposentados`, `02_corte`, `03_pens_atuais`, `04_pens_vac` |
| `rpps_dw.tbl_evolucao_funcional` | View Histórica | Movimentações de carreira e histórico de cargos ocupados pelo servidor ao longo do vínculo. | `NUMFUNC`, `NUMVINC`, `CARGO` | `01_aposentados`, `02_serv_corte_historico` |
| `rpps_dw.fato_folha_cabecalho` | Cubo / Fato Mensal | Cabeçalho de competências mensais da folha (+51 milhões de registros), usado para identificar o último cargo ativo (`MAX(MES_ANO)`). | `NUMFUNC`, `NUMVINC`, `CARGO` | `01_ativos_vigentes` |
| `rpps_dw.dim_carreiras` | Tabela Dimensão | Catálogo descritivo de cargos e carreiras públicas (`NOME`). | `CARGO` | `01_ativos`, `01_aposentados`, `02_corte` |
| `rpps_dw.tbl_beneficiarios_previdenciarios` | View de Benefícios | Ponte de relacionamento entre o instituidor (legador) e seus dependentes/pensionistas (`PARENTESCO`, `NUM_PENSAO`). | `NUM_PEN_FUNC`, `NUM_PEN_VINC`, `NUM_MATRICULA_LEGADOR` | `02_corte`, `03_pens_atuais`, `04_pens_vac` |
| `rpps_dw.tbl_instituidor_legador` | View de Instituidores | Registro do servidor originador da pensão por morte e sua respectiva data de óbito (`DATA_OBITO`). | `NUM_PENSAO` | `03_pens_atuais`, `04_pens_vac` |
| `rpps_dw.tbl_historico_beneficiarios_legado` | Tabela Legada | Base histórica complementar de beneficiários cessados/falecidos desde 2015 (`BEN_DTCESSA`, `BEN_TIPO`). | `LEG_NUMERO`, `BEN_CODIGO` | `04_pensionistas_historico_obitos` |
| `rpps_dw.tbl_historico_legadores_legado` | Tabela Legada | Base histórica complementar de instituidores vinculados aos registros legados (`LEG_REGFUNC`, `LEG_DTOBITO`). | `LEG_REGFUNC` (`= LEG_NUMERO`) | `04_pensionistas_historico_obitos` |

---

## 3. Dicionário de Atributos Padronizados de Saída

Os layouts finais projetam colunas padronizadas conforme especificações da avaliação atuarial:

| Coluna de Saída (Layout) | Tipo Lógico | Formato / Domínio | Descrição Técnica e Regra de Saneamento |
| :--- | :--- | :--- | :--- |
| `ID_SEGURADO_MATRICULA` | `VARCHAR` | `NUMFUNC-NUMVINC` | Identificador único composto do vínculo do servidor (concatenado apenas na projeção final). |
| `ID_PENSIONISTA_MATRICULA` | `VARCHAR` | `NUMFUNC-NUMVINC` ou `NUMFUNCNUMVINC` | Identificador único do vínculo do beneficiário de pensão (`EMP_CODIGO = 6` ou `LEG_NUMERO-BEN_CODIGO`). |
| `ID_INSTITUIDOR_MATRICULA` | `INT / BIGINT` | Numérico | Matrícula funcional do segurado gerador do benefício de pensão por morte. |
| `CO_COMP_MASSA` | `INT / VARCHAR` | `1` ou `2` (`NULL` no legado) | Código de segregação da massa previdenciária (`1` = Massa Civil / Geral; `2` = Aposentados específicos). |
| `CO_SEXO_SEGURADO` / `CO_SEXO_PENSIONISTA` | `VARCHAR(1)` | `'1'` (Fem), `'2'` (Masc) | Tradução obrigatória para aplicação das tábuas biométricas segregadas por sexo (Portaria MTP 1.467/2022, Art. 36). |
| `DT_NASC_SEGURADO` / `DT_NASC_PENSIONISTA` | `VARCHAR(10)` | `DD/MM/AAAA` | Data de nascimento formatada via `CONVERT(..., 103)`. |
| `DT_ING_ENTE` | `VARCHAR(10)` | `DD/MM/AAAA` | Data de início de exercício no ente federativo (`MIN(TRY_CONVERT(DATE, DTEXERC, 103))` para aposentados/corte; `DTEXERC` para ativos). |
| `DT_APOSENTADORIA_PROGRAMADA` | `VARCHAR(10)` | `DD/MM/AAAA` | Data de concessão de aposentadoria voluntária, compulsória ou especial (exclui prefixos `INV%`, `INC%` e `APOS_INVALIDEZ`). |
| `DT_APOSENTADORIA_POR_INVALIDEZ` | `VARCHAR(10)` | `DD/MM/AAAA` | Data de concessão de aposentadoria por incapacidade permanente (`INV%`, `INC%` ou `APOS_INVALIDEZ`). |
| `DT_EXONERACAO` | `VARCHAR(10)` | `DD/MM/AAAA` | Data de desligamento em vida (Listas B e C de vacância), suprimida caso haja óbito registrado no mesmo vínculo. |
| `DT_OBITO` / `DT_OBITO_PENSIONISTA` | `VARCHAR(10)` | `DD/MM/AAAA` | Data de falecimento do segurado ou pensionista (Lista A de vacância ou `BEN_TIPO = '1'`). |
| `QTD_PENSIONISTAS` | `INT` | `>= 0` | Quantidade de indivíduos únicos (`COUNT(DISTINCT NUM_PEN_FUNC)`) vinculados ao instituidor desligado. |
| `CO_TIPO_RELACAO` | `VARCHAR(1)` | `'1'` a `'6'` | Grau de parentesco homologado (`1`=Cônjuge/Comp., `2`=Filho Válido, `3`=Filho Deficiente, `4`=Genitor, `5`=Irmão, `6`=Outros). |
| `CO_CONDICAO` | `VARCHAR(1)` | `'1'` ou `'2'` | Condição de invalidez do pensionista (`1` = Válido; `2` = Inválido/Deficiente). |
| `CO_DURACAO` | `VARCHAR` | Código nativo | Indicador de vitaliciedade ou temporariedade do benefício (`TIPOVINC` ou `BEN_TIPO`). |
| `NO_CARREIRA` | `VARCHAR` | Texto | Denominação da última carreira/cargo ocupado pelo segurado (`dim_carreiras.NOME`). |
