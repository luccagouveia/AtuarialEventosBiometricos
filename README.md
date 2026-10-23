# AtuarialEventosBiometricos

Este projeto centraliza e consolida as bases de dados para o Censo Previdenciário e Testes de Aderência Atuarial do Regime Próprio de Previdência Social (RPPS). A arquitetura foi projetada de forma modular para mitigar erros de conexão e garantir escalabilidade para futuras transformações via dbt e automações em Python.

##  Escopo dos Layouts (Data de Referência: 31/05/2026)

### 1. Layout: ativos_aposentados (Em Desenvolvimento)
*   **Regra de População:** Informar **TODOS** os servidores atualmente em atividade e **TODOS** os aposentados vigentes.
*   **Coorte Histórica:** Incluir **TODOS** os servidores que foram exonerados, demitidos, se aposentaram ou faleceram estritamente entre **01/01/2015 e 31/05/2026** (inclusive aposentados que faleceram neste mesmo período).

### 2. Layout: pensionistas (Planejado)
*   **Regra de População:** Informar **TODOS** os atuais pensionistas vigentes na folha de pagamento.
*   **Coorte Histórica:** Incluir **TODOS** os pensionistas que faleceram ou que tiveram o seu benefício de pensão encerrado estritamente entre **01/01/2015 e 31/05/2026**.

---
##  Cronograma de Sincronização (Git Workflow)
*   **Fase atual:** Desenvolvimento e homologação de queries segregadas do layout `ativos_aposentados`.
*   **Sincronização diária:** Commits mandatórios ao final de cada marco de integridade validado.

