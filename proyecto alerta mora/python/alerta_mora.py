import pandas as pd
import pyodbc
from datetime import date

# 1. Conexión: usa el mismo nombre de servidor que en SSMS
SERVIDOR = r"localhost\SQLEXPRESS"

conexion = pyodbc.connect(
    "DRIVER={SQL Server};"
    f"SERVER={SERVIDOR};"
    "DATABASE=ValleVerde;"
    "Trusted_Connection=yes;"
)

# 2. Consulta: reutiliza la vista que ya creaste
consulta = """
SELECT nombre, departamento, producto,
       dias_atraso, monto_vencido, saldo_total
FROM vw_estado_creditos
WHERE estado = N'1-30 días'
ORDER BY saldo_total DESC
"""

df = pd.read_sql(consulta, conexion)
conexion.close()

# 3. Clasificar la prioridad según el saldo en riesgo
df["prioridad"] = pd.cut(
    df["saldo_total"],
    bins=[0, 50000, 100000, float("inf")],
    labels=["Baja", "Media", "Alta"],
)

# 4. Resumen en pantalla
print(f"Créditos en alerta: {len(df)}")
print(f"Saldo en riesgo: L {df['saldo_total'].sum():,.2f}")
print(df["prioridad"].value_counts())

# 5. Exportar a Excel con la fecha en el nombre
archivo = f"alerta_mora_{date.today():%Y%m%d}.xlsx"
df.to_excel(archivo, index=False, sheet_name="Alerta")
print("Archivo generado:", archivo)
