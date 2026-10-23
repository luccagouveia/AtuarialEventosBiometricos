SELECT TOP 100
    CONCAT(V.id_funcionario, '-', V.id_vinculo) AS ID_SEGURADO_MATRICULA,
    1 AS CO_COMP_MASSA,
    F.sexo AS CO_SEXO_SEGURADO,
    F.data_nascimento AS DT_NASC_SEGURADO,
    I.dt_ingresso_minima AS DT_ING_ENTE,
    NULL AS DT_EXONERACAO,
    NULL AS DT_APOSENTADORIA_PROGRAMADA,
    NULL AS DT_APOSENTADORIA_POR_INVALIDEZ,
    NULL AS DT_OBITO,
    0 AS QTD_PENSIONISTAS,
    AB.dt_inicio_abono AS DT_INICIO_ABONO_PERMANENCIA,
    CAR.nome_carreira AS NO_CARREIRA
FROM (
    SELECT id_funcionario, id_vinculo, regime_previdenciario, forma_vacancia, tipo_aposentadoria, id_empresa
    FROM [rpps_dw].[prod].[tbl_historico_vinculos]
    WHERE regime_previdenciario = 'RPPS'
      AND (forma_vacancia IS NULL OR forma_vacancia = '' OR forma_vacancia NOT IN ('APOSENTADORIA RPPS', 'EXE FATO APO 70 ANOS', 'APOSEN DEF CUMP JUD', 'APOSEN PROV CUMP JUD', 'APOSEN / CASSACAO', 'INVAL / INCAP', 'APOSENT INV RGPS', 'EXONERACAO', 'DEMISSAO', 'FALECIMENTO'))
      AND (tipo_aposentadoria IS NULL OR tipo_aposentadoria = '' OR tipo_aposentadoria = 'CANCEL EFEITOS APOS')
) V
INNER JOIN [rpps_dw].[prod].[tbl_cadastro_biografico] F ON V.id_funcionario = F.id_biografico
WHERE NOT EXISTS (
    SELECT 1 FROM [rpps_dw].[prod].[tbl_controle_encerramento] VI 
    WHERE VI.id_funcionario = V.id_funcionario AND VI.id_vinculo = V.id_vinculo AND VI.data_vacancia IS NOT NULL AND VI.data_vacancia <= '2026-05-31'
)
LEFT JOIN (
    SELECT id_funcionario, MIN(CASE WHEN data_exercicio LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, data_exercicio, 103) ELSE TRY_CONVERT(DATE, data_exercicio, 120) END) AS dt_ingresso_minima 
    FROM [rpps_dw].[prod].[tbl_historico_vinculos] 
    GROUP BY id_funcionario
) I ON V.id_funcionario = I.id_funcionario
LEFT JOIN (
    SELECT id_funcionario, id_vinculo, id_empresa, MIN(mes_ano_folha) AS dt_inicio_abono 
    FROM [rpps_dw].[prod].[fato_financeira_cubo] 
    WHERE código_rubrica = 9017 
    GROUP BY id_funcionario, id_vinculo, id_empresa
) AB ON V.id_funcionario = AB.id_funcionario AND V.id_vinculo = AB.id_vinculo AND V.id_empresa = AB.id_empresa
LEFT JOIN (
    SELECT id_funcionario, id_vinculo, nome_carreira 
    FROM (
        SELECT e.id_funcionario, e.id_vinculo, c.nome_cargo AS nome_carreira, 
               ROW_NUMBER() OVER (PARTITION BY e.id_funcionario, e.id_vinculo ORDER BY CASE WHEN e.data_fim IS NULL THEN 1 ELSE 0 END DESC, e.data_inicio DESC) AS RN 
        FROM [rpps_dw].[prod].[tbl_evolucao_cargos] e 
        INNER JOIN [rpps_dw].[prod].[dim_cargos] c ON e.id_cargo = c.id_cargo
    ) HistCargos WHERE RN = 1
) CAR ON V.id_funcionario = CAR.id_funcionario AND V.id_vinculo = CAR.id_vinculo;
