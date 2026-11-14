-- Análisis de mora - Cooperativa Valle Verde (datos simulados)
-- Fecha de corte: variable @corte en cada bloque.
-- Atraso = días desde la cuota impaga más antigua hasta la fecha de corte.
-- Cada bloque se ejecuta por separado (están divididos con GO).

USE ValleVerde;
GO

-- =====================================================================
-- 1. Mora por tramos de días de atraso
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH mora AS (
    SELECT c.id_credito,
           DATEDIFF(DAY, MIN(q.fecha_vencimiento), @corte) AS dias_atraso,
           SUM(q.monto_cuota) AS monto_vencido
    FROM creditos c
    JOIN cuotas q ON q.id_credito = c.id_credito
    WHERE q.fecha_vencimiento <= @corte
      AND q.fecha_pago IS NULL
    GROUP BY c.id_credito
)
SELECT CASE
           WHEN dias_atraso <= 30 THEN '1-30 días'
           WHEN dias_atraso <= 60 THEN '31-60 días'
           WHEN dias_atraso <= 90 THEN '61-90 días'
           ELSE 'Más de 90 días'
       END AS tramo,
       COUNT(*) AS creditos,
       SUM(monto_vencido) AS monto_vencido
FROM mora
GROUP BY CASE
           WHEN dias_atraso <= 30 THEN '1-30 días'
           WHEN dias_atraso <= 60 THEN '31-60 días'
           WHEN dias_atraso <= 90 THEN '61-90 días'
           ELSE 'Más de 90 días'
         END
ORDER BY MIN(dias_atraso);
GO

-- =====================================================================
-- 2. Índice de mora de la cartera
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH saldos AS (
    SELECT id_credito,
           SUM(monto_cuota) AS saldo,
           MAX(CASE WHEN fecha_vencimiento <= @corte
                    THEN 1 ELSE 0 END) AS en_mora
    FROM cuotas
    WHERE fecha_pago IS NULL
    GROUP BY id_credito
)
SELECT COUNT(*) AS creditos_activos,
       SUM(saldo) AS cartera_total,
       SUM(CASE WHEN en_mora = 1 THEN saldo ELSE 0 END) AS cartera_en_mora,
       CAST(100.0 * SUM(CASE WHEN en_mora = 1 THEN saldo ELSE 0 END)
            / SUM(saldo) AS DECIMAL(5,2)) AS pct_mora
FROM saldos;
GO

-- =====================================================================
-- 3. Índice de mora por producto
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH saldos AS (
    SELECT id_credito,
           SUM(monto_cuota) AS saldo,
           MAX(CASE WHEN fecha_vencimiento <= @corte
                    THEN 1 ELSE 0 END) AS en_mora
    FROM cuotas
    WHERE fecha_pago IS NULL
    GROUP BY id_credito
)
SELECT c.producto,
       COUNT(*) AS creditos,
       SUM(s.saldo) AS cartera_total,
       SUM(CASE WHEN s.en_mora = 1 THEN s.saldo ELSE 0 END) AS cartera_en_mora,
       CAST(100.0 * SUM(CASE WHEN s.en_mora = 1 THEN s.saldo ELSE 0 END)
            / SUM(s.saldo) AS DECIMAL(5,2)) AS pct_mora
FROM saldos s
JOIN creditos c ON c.id_credito = s.id_credito
GROUP BY c.producto
ORDER BY pct_mora DESC;
GO

-- =====================================================================
-- 4. Lista de alerta temprana: créditos con 1 a 30 días de atraso,
--    ordenados por saldo en riesgo
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH mora AS (
    SELECT id_credito,
           DATEDIFF(DAY, MIN(fecha_vencimiento), @corte) AS dias_atraso,
           COUNT(*) AS cuotas_vencidas,
           SUM(monto_cuota) AS monto_vencido
    FROM cuotas
    WHERE fecha_vencimiento <= @corte
      AND fecha_pago IS NULL
    GROUP BY id_credito
),
saldos AS (
    SELECT id_credito, SUM(monto_cuota) AS saldo_total
    FROM cuotas
    WHERE fecha_pago IS NULL
    GROUP BY id_credito
)
SELECT cl.nombre,
       cl.departamento,
       c.producto,
       m.id_credito,
       m.dias_atraso,
       m.cuotas_vencidas,
       m.monto_vencido,
       s.saldo_total
FROM mora m
JOIN saldos s    ON s.id_credito = m.id_credito
JOIN creditos c  ON c.id_credito = m.id_credito
JOIN clientes cl ON cl.id_cliente = c.id_cliente
WHERE m.dias_atraso <= 30
ORDER BY s.saldo_total DESC;
GO

-- =====================================================================
-- 5. Clientes con más de un crédito en alerta temprana
--    (se agrupa por id_cliente: puede haber clientes con el mismo nombre)
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH mora AS (
    SELECT id_credito,
           DATEDIFF(DAY, MIN(fecha_vencimiento), @corte) AS dias_atraso,
           SUM(monto_cuota) AS monto_vencido
    FROM cuotas
    WHERE fecha_vencimiento <= @corte
      AND fecha_pago IS NULL
    GROUP BY id_credito
)
SELECT cl.id_cliente,
       cl.nombre,
       COUNT(*) AS creditos_en_alerta,
       SUM(m.monto_vencido) AS total_vencido
FROM mora m
JOIN creditos c  ON c.id_credito = m.id_credito
JOIN clientes cl ON cl.id_cliente = c.id_cliente
WHERE m.dias_atraso <= 30
GROUP BY cl.id_cliente, cl.nombre
HAVING COUNT(*) > 1
ORDER BY creditos_en_alerta DESC;
GO

-- =====================================================================
-- 6. Señales de deterioro: créditos al día cuyas últimas 3 cuotas
--    se pagaron en promedio con 15 días o más de retraso
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH pagadas AS (
    SELECT id_credito,
           DATEDIFF(DAY, fecha_vencimiento, fecha_pago) AS dias_tarde,
           ROW_NUMBER() OVER (PARTITION BY id_credito
                              ORDER BY numero_cuota DESC) AS orden
    FROM cuotas
    WHERE fecha_pago IS NOT NULL
),
ultimas AS (
    SELECT id_credito,
           CAST(AVG(1.0 * dias_tarde) AS DECIMAL(5,1)) AS promedio_dias_tarde
    FROM pagadas
    WHERE orden <= 3
    GROUP BY id_credito
    HAVING COUNT(*) = 3 AND AVG(1.0 * dias_tarde) >= 15
),
saldos AS (
    SELECT id_credito,
           SUM(monto_cuota) AS saldo_total,
           MAX(CASE WHEN fecha_vencimiento <= @corte
                    THEN 1 ELSE 0 END) AS en_mora
    FROM cuotas
    WHERE fecha_pago IS NULL
    GROUP BY id_credito
)
SELECT cl.id_cliente, cl.nombre, u.id_credito,
       u.promedio_dias_tarde, s.saldo_total
FROM ultimas u
JOIN saldos s    ON s.id_credito = u.id_credito
JOIN creditos c  ON c.id_credito = u.id_credito
JOIN clientes cl ON cl.id_cliente = c.id_cliente
WHERE s.en_mora = 0
ORDER BY u.promedio_dias_tarde DESC;
GO

-- =====================================================================
-- 7. Cosechas: % de créditos en mora por trimestre de desembolso
-- =====================================================================
DECLARE @corte DATE = '2026-10-31';

WITH mora AS (
    SELECT DISTINCT id_credito
    FROM cuotas
    WHERE fecha_vencimiento <= @corte
      AND fecha_pago IS NULL
)
SELECT CONCAT(YEAR(c.fecha_desembolso), '-T',
              DATEPART(QUARTER, c.fecha_desembolso)) AS cosecha,
       COUNT(*) AS creditos,
       SUM(c.monto) AS monto_desembolsado,
       COUNT(m.id_credito) AS creditos_en_mora,
       CAST(100.0 * COUNT(m.id_credito) / COUNT(*)
            AS DECIMAL(5,2)) AS pct_en_mora
FROM creditos c
LEFT JOIN mora m ON m.id_credito = c.id_credito
GROUP BY CONCAT(YEAR(c.fecha_desembolso), '-T',
                DATEPART(QUARTER, c.fecha_desembolso))
ORDER BY cosecha;
GO
