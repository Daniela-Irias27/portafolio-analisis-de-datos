-- Vista: estado de cada crédito a la fecha de corte.
-- Una fila por crédito, con saldo, monto vencido, días de atraso y tramo de mora.
-- Es la fuente del tablero de Power BI y del script de Python.
-- Atraso = días desde la cuota impaga más antigua hasta la fecha de corte.

USE ValleVerde;
GO
CREATE OR ALTER VIEW vw_estado_creditos AS
WITH p AS (
    SELECT CAST('2026-10-31' AS DATE) AS corte
),
pend AS (
    SELECT q.id_credito,
           SUM(q.monto_cuota) AS saldo_total,
           SUM(CASE WHEN q.fecha_vencimiento <= p.corte
                    THEN q.monto_cuota ELSE 0 END) AS monto_vencido,
           SUM(CASE WHEN q.fecha_vencimiento <= p.corte
                    THEN 1 ELSE 0 END) AS cuotas_vencidas,
           MAX(CASE WHEN q.fecha_vencimiento <= p.corte
                    THEN DATEDIFF(DAY, q.fecha_vencimiento, p.corte)
                    ELSE 0 END) AS dias_atraso
    FROM cuotas q
    CROSS JOIN p
    WHERE q.fecha_pago IS NULL
    GROUP BY q.id_credito
)
SELECT c.id_credito, cl.id_cliente, cl.nombre, cl.departamento,
       cl.ocupacion, c.producto, c.monto, c.fecha_desembolso,
       ISNULL(pe.saldo_total, 0)     AS saldo_total,
       ISNULL(pe.monto_vencido, 0)   AS monto_vencido,
       ISNULL(pe.cuotas_vencidas, 0) AS cuotas_vencidas,
       ISNULL(pe.dias_atraso, 0)     AS dias_atraso,
       CASE WHEN pe.id_credito IS NULL THEN 'Cancelado'
            WHEN pe.dias_atraso = 0    THEN 'Al día'
            WHEN pe.dias_atraso <= 30  THEN '1-30 días'
            WHEN pe.dias_atraso <= 60  THEN '31-60 días'
            WHEN pe.dias_atraso <= 90  THEN '61-90 días'
            ELSE 'Más de 90 días' END AS estado
FROM creditos c
JOIN clientes cl ON cl.id_cliente = c.id_cliente
LEFT JOIN pend pe ON pe.id_credito = c.id_credito;
GO

-- Comprobación: debe sumar 595 créditos
SELECT estado, COUNT(*) AS creditos, SUM(saldo_total) AS saldo
FROM vw_estado_creditos
GROUP BY estado;
