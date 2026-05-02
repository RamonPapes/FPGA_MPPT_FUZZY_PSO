import pandas as pd
import numpy as np

INPUT_CSV = "archive\Apr_2023.csv"
OUTPUT_TXT = "dataset_scaled.txt"

df = pd.read_csv(INPUT_CSV)

df["Timestamp"] = pd.to_datetime(df["Timestamp"], errors="coerce")
df = df.dropna(subset=["Timestamp"])

# Filtra abril de 2023
df = df[
    (df["Timestamp"].dt.year == 2023) &
    (df["Timestamp"].dt.month == 4)
].copy()

# Escolha das colunas
power_col = "PVPCS_Active_Power"
voltage_col = "MG-LV-MSB_AC_Voltage"

df[power_col] = pd.to_numeric(df[power_col], errors="coerce")
df[voltage_col] = pd.to_numeric(df[voltage_col], errors="coerce")

df = df.dropna(subset=[power_col, voltage_col])
df = df[df[voltage_col] != 0]

# Estimativa simples de corrente: I = P / V
# Cuidado: depende da unidade da potência no dataset.
df["current_estimated"] = df[power_col] / df[voltage_col]

# Escalas do VHDL:
# voltage Q12.4  => valor inteiro = V * 16
# current Q1.15  => valor inteiro = I * 32768
df["voltage_scaled"] = np.round(df[voltage_col] * 16).astype(int)
df["current_scaled"] = np.round(df["current_estimated"] * 32768).astype(int)

# Limita para signed 16-bit
df["voltage_scaled"] = df["voltage_scaled"].clip(-32768, 32767)
df["current_scaled"] = df["current_scaled"].clip(-32768, 32767)

df[["voltage_scaled", "current_scaled"]].to_csv(
    OUTPUT_TXT,
    sep=" ",
    header=False,
    index=False
)

print(f"Gerado: {OUTPUT_TXT}")
print(f"Amostras: {len(df)}")
print(df[["Timestamp", voltage_col, power_col, "current_estimated", "voltage_scaled", "current_scaled"]].head())