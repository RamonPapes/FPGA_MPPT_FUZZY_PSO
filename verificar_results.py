import pandas as pd
import matplotlib.pyplot as plt

# =========================
# CONFIG
# =========================
INPUT_FILE = "resultados_hybrid.txt"

# Se quiser limitar para um trecho, altere aqui:
USE_SLICE = False
START = 0
END = 4500

# =========================
# LEITURA
# =========================


df = pd.read_csv("resultados_hybrid.txt", sep=r"\s+")

df["Vpv"] = df["voltage"] / 16.0
df["Ipv"] = df["current"] / 32768.0
df["sample"] = range(len(df))

# Pega só 4500 amostras, como no TCC
df = df.iloc[0:4500].copy()
df["sample"] = range(len(df))

if USE_SLICE:
    df = df.iloc[START:END].copy()
# =========================
# FIGURA 1 — estilo TCC
# Vpv, Ipv, Error, CE
# =========================
fig, axs = plt.subplots(4, 1, figsize=(10, 8), sharex=True)

axs[0].plot(df["sample"], df["Vpv"])
axs[0].set_title("Input - Vpv")
axs[0].set_ylabel("Voltage (V)")
axs[0].grid(True)

axs[1].plot(df["sample"], df["Ipv"])
axs[1].set_title("Input - Ipv")
axs[1].set_ylabel("Current (A)")
axs[1].grid(True)

axs[2].plot(df["sample"], df["error"])
axs[2].set_title("Error (ΔP/ΔV)")
axs[2].set_ylabel("Error")
axs[2].grid(True)

axs[3].plot(df["sample"], df["delta_e"])
axs[3].set_title("CE (ΔE)")
axs[3].set_ylabel("CE")
axs[3].set_xlabel("Samples")
axs[3].grid(True)

plt.tight_layout()
plt.savefig("grafico_estilo_tcc.png", dpi=300)
plt.show()

# =========================
# FIGURA 2 — duty e gbest
# =========================
plt.figure(figsize=(10, 4))
plt.plot(df["sample"], df["duty"], label="duty")
plt.plot(df["sample"], df["gbest_duty"], label="gbest_duty")
plt.title("Duty Cycle and Global Best Duty")
plt.xlabel("Samples")
plt.ylabel("Duty (%)")
plt.grid(True)
plt.legend()
plt.tight_layout()
plt.savefig("grafico_duty_gbest.png", dpi=300)
plt.show()

# =========================
# FIGURA 3 — gbest power
# =========================
plt.figure(figsize=(10, 4))
plt.plot(df["sample"], df["gbest_power"], label="gbest_power")
plt.title("Best Power Found")
plt.xlabel("Samples")
plt.ylabel("Internal Scaled Power")
plt.grid(True)
plt.legend()
plt.tight_layout()
plt.savefig("grafico_gbest_power.png", dpi=300)
plt.show()

# =========================
# FIGURA 4 — fuzzy_delta
# =========================
plt.figure(figsize=(10, 4))
plt.plot(df["sample"], df["fuzzy_delta"], label="fuzzy_delta")
plt.title("Fuzzy Output")
plt.xlabel("Samples")
plt.ylabel("Fuzzy Delta")
plt.grid(True)
plt.legend()
plt.tight_layout()
plt.savefig("grafico_fuzzy_delta.png", dpi=300)
plt.show()

# =========================
# Checagens simples
# =========================
print("Número de amostras:", len(df))
print("Duty min/max:", df["duty"].min(), df["duty"].max())
print("gbest_duty min/max:", df["gbest_duty"].min(), df["gbest_duty"].max())
print("gbest_power min/max:", df["gbest_power"].min(), df["gbest_power"].max())

monotonic_gbest = (df["gbest_power"].diff().fillna(0) >= 0).all()
print("gbest_power é monotônico não-decrescente?", monotonic_gbest)