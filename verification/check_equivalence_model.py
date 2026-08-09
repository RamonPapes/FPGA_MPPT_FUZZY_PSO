"""
Modelo de referencia em Python do controlador MPPT hibrido.

Transliteracao fiel das duas versoes do RTL:

  ref  -> RTL original (fuzzy avaliada duas vezes, enxame atualizado em
          paralelo, inteiros sem faixa declarada)
  new  -> RTL refatorado (fuzzy avaliada uma vez, enxame atualizado em serie,
          divisoes por constante feitas em magnitude, subtipos com faixa)

O script roda as duas versoes sobre o mesmo estimulo, compara amostra a
amostra e, na versao nova, verifica que nenhum valor sai da faixa declarada
no VHDL. Serve para validar a refatoracao sem depender de um simulador VHDL;
o testbench tb_equivalence.vhd faz a mesma checagem dentro do Questa.
"""

from __future__ import annotations

import argparse
import sys

N_PARTICLES = 10
DUTY_MIN = 0
DUTY_MAX = 100

FUZZY_RULES = [
    [-100, -80, -60, -40, -20, -10, 0],
    [-80, -60, -40, -20, -10, 0, 10],
    [-60, -40, -20, -10, 0, 10, 20],
    [-40, -20, -10, 0, 10, 20, 40],
    [-20, -10, 0, 10, 20, 40, 60],
    [-10, 0, 10, 20, 40, 60, 80],
    [0, 10, 20, 40, 60, 80, 100],
]


# ----------------------------------------------------------------------
# Aritmetica
# ----------------------------------------------------------------------


def vdiv(a: int, b: int) -> int:
    """Operador "/" do VHDL: divisao inteira truncada em direcao a zero."""
    q = abs(a) // abs(b)

    return -q if (a < 0) != (b < 0) else q


def div_trunc(num: int, den: int, num_bits: int) -> int:
    """Equivalente da funcao div_trunc do pacote refatorado."""
    assert den > 0, "den deve ser positivo"

    mag = abs(num)
    assert mag < (1 << num_bits), (
        f"div_trunc: numerador {num} nao cabe em {num_bits} bits sem sinal"
    )

    q = mag // den

    return -q if num < 0 else q


def clamp(x: int, low: int, high: int) -> int:
    if x < low:
        return low
    if x > high:
        return high
    return x


def sign_int(x: int) -> int:
    return (x > 0) - (x < 0)


# ----------------------------------------------------------------------
# Funcoes de pertinencia e motor fuzzy (identicos nas duas versoes)
# ----------------------------------------------------------------------


def triangle(x: int, a: int, b: int, c: int) -> int:
    if b <= a or c <= b:
        return 0
    if x <= a or x >= c:
        return 0
    if x == b:
        return 100
    if x < b:
        return ((x - a) * 100) // (b - a)
    return ((c - x) * 100) // (c - b)


def trap_neg(x: int, plateau_end: int, slope_start: int, slope_end: int) -> int:
    if slope_end <= slope_start:
        return 0
    if x <= plateau_end:
        return 100
    if x >= slope_end:
        return 0
    if x > slope_start:
        return ((slope_end - x) * 100) // (slope_end - slope_start)
    return 100


def trap_pos(x: int, slope_start: int, slope_end: int, plateau_start: int) -> int:
    if slope_end <= slope_start:
        return 0
    if x >= plateau_start:
        return 100
    if x <= slope_start:
        return 0
    if x < slope_end:
        return ((x - slope_start) * 100) // (slope_end - slope_start)
    return 100


def fuzzy_compute(e_in, de_in, deadzone, fuzzy_step, fuzzy_edge):
    e = clamp(e_in, -100, 100)
    de = clamp(de_in, -100, 100)

    step_v = clamp(fuzzy_step, 1, 49)
    edge_v = clamp(fuzzy_edge, (2 * step_v) + 1, 100)

    if abs(e) < deadzone and abs(de) < deadzone:
        return 0

    def memberships(x):
        return [
            trap_neg(x, -100, -edge_v, -(2 * step_v)),
            triangle(x, -edge_v, -(2 * step_v), -step_v),
            triangle(x, -(2 * step_v), -step_v, 0),
            triangle(x, -step_v, 0, step_v),
            triangle(x, 0, step_v, 2 * step_v),
            triangle(x, step_v, 2 * step_v, edge_v),
            trap_pos(x, 2 * step_v, edge_v, 100),
        ]

    mu_e = memberships(e)
    mu_de = memberships(de)

    numerator = 0
    denominator = 0

    for i in range(7):
        for j in range(7):
            min_mu = min(mu_e[i], mu_de[j])
            numerator += min_mu * FUZZY_RULES[i][j]
            denominator += min_mu

    if denominator != 0:
        return vdiv(numerator, denominator)

    return 0


def fokker_step_from_fuzzy(fuzzy_val, step_min_g, step_max_g):
    step_min = min(step_min_g, step_max_g)
    step_max = max(step_min_g, step_max_g)

    mag = abs(fuzzy_val)
    step_val = step_min + ((mag * (step_max - step_min)) // 100)

    return clamp(step_val, step_min, step_max)


def pno_direction(delta_p, delta_v):
    if delta_p > 0:
        return sign_int(delta_v)
    if delta_p < 0:
        return -sign_int(delta_v)
    return 0


def next_lfsr(x: int) -> int:
    bit = ((x >> 15) ^ (x >> 13) ^ (x >> 12) ^ (x >> 10)) & 1

    return ((x << 1) | bit) & 0xFFFF


def rand_0_100(x: int) -> int:
    return (x & 0xFF) % 101


def rand_rho(x: int, rho_min: int, rho_max: int) -> int:
    lo = min(rho_min, rho_max)
    hi = max(rho_min, rho_max)

    return lo + ((x & 0xFF) % (hi - lo + 1))


# ----------------------------------------------------------------------
# Verificador de faixa dos subtipos do VHDL refatorado
# ----------------------------------------------------------------------

RANGES = {
    "duty_t": (0, 100),
    "err_t": (-100, 100),
    "rule_t": (-100, 100),
    "vel_t": (-512, 511),
    "step_t": (0, 255),
    "coeff_t": (0, 255),
    "power_t": (-32768, 32767),
    "volt_t": (-32768, 32767),
    "delta_t": (-65536, 65535),
    "age_t": (0, 65535),
    "drop_t": (0, 65535),
    "vel_acc_t": (-8192, 8191),
    "pos_acc_t": (-8192, 8191),
    "error_num_t": (-(2**24), 2**24 - 1),
    "raw_power_t": (-(2**30), 2**30 - 1),
    "drop_cmp_t": (-(2**23), 2**23 - 1),
    "defuzz_num_t": (-490000, 490000),
    "defuzz_den_t": (0, 4900),
}


class RangeViolation(Exception):
    pass


def rng(name: str, value: int, ctx: str = "") -> int:
    lo, hi = RANGES[name]

    if not (lo <= value <= hi):
        raise RangeViolation(
            f"{name} estourou: {value} fora de [{lo},{hi}] {ctx}"
        )

    return value


# ----------------------------------------------------------------------
# Controlador
# ----------------------------------------------------------------------

DEFAULT_GENERICS = dict(
    SETTLE_CYCLES=1,
    W_PSO_G=70,
    C1_PSO_G=60,
    C2_PSO_G=60,
    RHO_MIN_G=55,
    RHO_MAX_G=65,
    VEL_MIN_G=-20,
    VEL_MAX_G=20,
    DEADZONE_G=1,
    SEARCH_RADIUS_G=10,
    FOKKER_STEP_MIN_G=1,
    FOKKER_STEP_MAX_G=4,
    FUZZY_STEP_G=40,
    FUZZY_EDGE_G=100,
    POWER_SCALE_DEN_G=65536,
    ERROR_GAIN_G=1,
    DELTA_V_MIN_G=16,
    DUTY_DIRECTION_G=1,
    SEARCH_CENTER_MODE_G=2,
    MEMORY_HALF_LIFE_G=300,
    MAX_PBEST_AGE_G=500,
    ENABLE_CHANGE_DETECTION_G=0,
    DROP_THRESHOLD_PERCENT_G=70,
    DROP_PATIENCE_G=30,
)

ATTRACT_BITS = 23
INERTIA_BITS = 18
AGED_BITS = 30


class Controller:
    """variant: 'ref' (RTL original) ou 'new' (RTL refatorado)."""

    def __init__(self, variant: str, g: dict):
        assert variant in ("ref", "new")
        self.variant = variant
        self.g = g
        self.check = variant == "new"

        seed = 0xACE1
        pos = []
        for _ in range(N_PARTICLES):
            seed = next_lfsr(seed)
            pos.append(rand_0_100(seed))

        self.INIT_POS = list(pos)

        if g["MEMORY_HALF_LIFE_G"] <= 0:
            lam = 10000
        else:
            lam = 10000 - ((693 * 10000) // (g["MEMORY_HALF_LIFE_G"] * 1000))

        self.LAMBDA_NUM = clamp(lam, 0, 10000)

        self.reset()

    def reset(self):
        self.particle_pos = list(self.INIT_POS)
        self.particle_vel = [0] * N_PARTICLES
        self.pbest_pos = list(self.INIT_POS)
        self.pbest_power = [0] * N_PARTICLES
        self.pbest_age = [0] * N_PARTICLES

        self.rho1 = [53] * N_PARTICLES
        self.rho2 = [53] * N_PARTICLES

        self.gbest_pos = 50
        self.gbest_power = 0
        self.drop_counter = 0

        self.current_idx = 0
        self.swarm_idx = 0
        self.wait_counter = 0

        self.prev_power = 0
        self.prev_voltage = 0
        self.prev_error = 0

        self.error_reg = 0
        self.delta_e_reg = 0
        self.fuzzy_delta = 0

        self.duty_reg = 50
        self.pno_candidate = 50
        self.search_center = 50
        self.fokker_step = 1
        self.duty_out = 50

        self.store_valid = 0
        self.lfsr = 0xACE1
        self.state = "APPLY_PARTICLE"

    # ---------------- blocos combinacionais ----------------

    def comb_measurement(self, current_in, voltage_in):
        g = self.g

        voltage_now = voltage_in
        raw = current_in * voltage_now

        if self.check:
            rng("raw_power_t", raw, "produto V*I")

        den = g["POWER_SCALE_DEN_G"] if g["POWER_SCALE_DEN_G"] > 0 else 1
        power_now = vdiv(raw, den)

        delta_p = power_now - self.prev_power
        delta_v = voltage_now - self.prev_voltage

        gain = g["ERROR_GAIN_G"] if g["ERROR_GAIN_G"] > 0 else 1
        dvmin = g["DELTA_V_MIN_G"] if g["DELTA_V_MIN_G"] > 0 else 1

        if abs(delta_v) < dvmin:
            error_raw = 0
        else:
            num = delta_p * gain

            if self.check:
                rng("error_num_t", num, "numerador de dP/dV")

            error_raw = vdiv(num, delta_v)

        error_next = clamp(error_raw, -100, 100)
        delta_e_next = clamp(error_next - self.prev_error, -100, 100)

        if self.check:
            rng("volt_t", voltage_now)
            rng("power_t", power_now)
            rng("delta_t", delta_p)
            rng("delta_t", delta_v)
            rng("err_t", error_next)
            rng("err_t", delta_e_next)

        return power_now, voltage_now, delta_p, delta_v, error_next, delta_e_next

    def comb_fuzzy(self, delta_p, delta_v, error_in, delta_e_in):
        g = self.g

        fuzzy_val = fuzzy_compute(
            error_in, delta_e_in, g["DEADZONE_G"], g["FUZZY_STEP_G"], g["FUZZY_EDGE_G"]
        )

        if self.variant == "ref":
            # O RTL original recalculava a fuzzy dentro de fokker_planck_step.
            fuzzy_for_step = fuzzy_compute(
                error_in,
                delta_e_in,
                g["DEADZONE_G"],
                g["FUZZY_STEP_G"],
                g["FUZZY_EDGE_G"],
            )
        else:
            fuzzy_for_step = fuzzy_val

        step = fokker_step_from_fuzzy(
            fuzzy_for_step, g["FOKKER_STEP_MIN_G"], g["FOKKER_STEP_MAX_G"]
        )

        d = pno_direction(delta_p, delta_v)
        if d == 0:
            d = sign_int(fuzzy_val)

        if d == 0:
            refined = self.pno_candidate
        else:
            refined = clamp(
                self.pno_candidate + (g["DUTY_DIRECTION_G"] * d * step),
                DUTY_MIN,
                DUTY_MAX,
            )

        if self.check:
            rng("rule_t", fuzzy_val)
            rng("step_t", step)
            rng("duty_t", refined)

        return fuzzy_val, step, refined

    def comb_search_window(self):
        r = self.g["SEARCH_RADIUS_G"]

        return (
            clamp(self.search_center - r, DUTY_MIN, DUTY_MAX),
            clamp(self.search_center + r, DUTY_MIN, DUTY_MAX),
        )

    def particle_update(self, i, low, high):
        g = self.g

        if low > high:
            low, high = high, low

        cog_n = g["C1_PSO_G"] * self.rho1[i] * (self.pbest_pos[i] - self.particle_pos[i])
        soc_n = g["C2_PSO_G"] * self.rho2[i] * (self.gbest_pos - self.particle_pos[i])
        ine_n = g["W_PSO_G"] * self.particle_vel[i]

        if self.variant == "new":
            rng("vel_t", self.particle_vel[i], "velocidade registrada")

            cognitive = div_trunc(cog_n, 10000, ATTRACT_BITS)
            social = div_trunc(soc_n, 10000, ATTRACT_BITS)
            inertia = div_trunc(ine_n, 100, INERTIA_BITS)
        else:
            cognitive = vdiv(cog_n, 10000)
            social = vdiv(soc_n, 10000)
            inertia = vdiv(ine_n, 100)

        v_new = inertia + cognitive + social

        if self.check:
            rng("vel_acc_t", v_new, "soma dos termos de velocidade")

        v_sat = clamp(v_new, g["VEL_MIN_G"], g["VEL_MAX_G"])

        p_new = self.particle_pos[i] + v_sat

        if self.check:
            rng("pos_acc_t", p_new, "posicao antes da saturacao")

        p_new = clamp(p_new, low, high)
        p_new = clamp(p_new, DUTY_MIN, DUTY_MAX)

        if self.check:
            rng("vel_t", v_sat)
            rng("duty_t", p_new)

        return p_new, v_sat

    def comb_best_tracker(self, power_now):
        g = self.g

        power_for_best = max(power_now, 0)

        best_power = 0
        best_pos = self.pbest_pos[0]

        pos_n = [0] * N_PARTICLES
        pow_n = [0] * N_PARTICLES
        age_n = [0] * N_PARTICLES

        for i in range(N_PARTICLES):
            prod = self.pbest_power[i] * self.LAMBDA_NUM

            if self.variant == "new":
                aged = div_trunc(prod, 10000, AGED_BITS)
            else:
                aged = vdiv(prod, 10000)

            upd_power = aged
            upd_pos = self.pbest_pos[i]
            raw_age = self.pbest_age[i] + 1

            if self.variant == "new":
                upd_age = min(raw_age, RANGES["age_t"][1])
                assert upd_age == raw_age, "saturacao de idade alterou o comportamento"
            else:
                upd_age = raw_age

            if i == self.current_idx:
                if power_for_best > aged or self.pbest_age[i] >= g["MAX_PBEST_AGE_G"]:
                    upd_power = power_for_best
                    upd_pos = self.duty_reg
                    upd_age = 0

            pow_n[i] = upd_power
            pos_n[i] = upd_pos
            age_n[i] = upd_age

            if i == 0 or upd_power > best_power:
                best_power = upd_power
                best_pos = upd_pos

            if self.check:
                rng("power_t", upd_power)
                rng("duty_t", upd_pos)
                rng("age_t", upd_age)

        if g["ENABLE_CHANGE_DETECTION_G"] != 0:
            lhs = power_for_best * 100
            rhs = best_power * g["DROP_THRESHOLD_PERCENT_G"]

            if self.check:
                rng("drop_cmp_t", lhs)
                rng("drop_cmp_t", rhs)

            if best_power > 0 and lhs < rhs:
                if self.drop_counter >= g["DROP_PATIENCE_G"] - 1:
                    pow_n = [power_for_best] * N_PARTICLES
                    pos_n = list(self.particle_pos)
                    age_n = [0] * N_PARTICLES
                    gb_power = power_for_best
                    gb_pos = self.duty_reg
                    drop_next = 0
                else:
                    gb_power = best_power
                    gb_pos = best_pos
                    raw_drop = self.drop_counter + 1

                    if self.variant == "new":
                        drop_next = min(raw_drop, RANGES["drop_t"][1])
                        assert drop_next == raw_drop, "saturacao de drop_counter atuou"
                    else:
                        drop_next = raw_drop
            else:
                gb_power = best_power
                gb_pos = best_pos
                drop_next = 0
        else:
            gb_power = best_power
            gb_pos = best_pos
            drop_next = 0

        return pos_n, pow_n, age_n, gb_pos, gb_power, drop_next

    def comb_random_coeff(self):
        g = self.g
        lf = self.lfsr
        r1 = [0] * N_PARTICLES
        r2 = [0] * N_PARTICLES

        for i in range(N_PARTICLES):
            lf = next_lfsr(lf)
            r1[i] = rand_rho(lf, g["RHO_MIN_G"], g["RHO_MAX_G"])
            lf = next_lfsr(lf)
            r2[i] = rand_rho(lf, g["RHO_MIN_G"], g["RHO_MAX_G"])

        if self.check:
            for i in range(N_PARTICLES):
                rng("coeff_t", r1[i])
                rng("coeff_t", r2[i])

        return r1, r2, lf

    # ---------------- borda de clock ----------------

    def tick(self, current_in, voltage_in):
        g = self.g

        power_now, voltage_now, delta_p, delta_v, err_next, de_next = (
            self.comb_measurement(current_in, voltage_in)
        )
        fuzzy_val, step, refined = self.comb_fuzzy(delta_p, delta_v, err_next, de_next)
        low, high = self.comb_search_window()

        self.store_valid = 0
        state = self.state

        if state == "APPLY_PARTICLE":
            self.duty_reg = self.particle_pos[self.current_idx]
            self.duty_out = self.particle_pos[self.current_idx]
            self.wait_counter = 0
            self.state = "WAIT_SETTLE"

        elif state == "WAIT_SETTLE":
            if self.wait_counter < g["SETTLE_CYCLES"]:
                self.wait_counter += 1
            else:
                self.state = "SAMPLE_AND_UPDATE"

        elif state == "SAMPLE_AND_UPDATE":
            pos_n, pow_n, age_n, gb_pos, gb_power, drop_next = self.comb_best_tracker(
                power_now
            )

            self.error_reg = err_next
            self.delta_e_reg = de_next
            self.fuzzy_delta = fuzzy_val
            self.fokker_step = step
            self.pno_candidate = refined

            self.pbest_pos = pos_n
            self.pbest_power = pow_n
            self.pbest_age = age_n
            self.gbest_pos = gb_pos
            self.gbest_power = gb_power
            self.drop_counter = drop_next

            self.prev_power = power_now
            self.prev_voltage = voltage_now
            self.prev_error = err_next

            self.store_valid = 1

            if self.current_idx == N_PARTICLES - 1:
                self.current_idx = 0
                self.state = "PREPARE_SWARM"
            else:
                self.current_idx += 1
                self.state = "APPLY_PARTICLE"

        elif state == "PREPARE_SWARM":
            mode = g["SEARCH_CENTER_MODE_G"]

            if mode == 0:
                self.search_center = self.pno_candidate
            elif mode == 1:
                self.search_center = self.gbest_pos
            else:
                self.search_center = clamp(
                    vdiv(self.gbest_pos + self.pno_candidate, 2), DUTY_MIN, DUTY_MAX
                )

            r1, r2, lf = self.comb_random_coeff()
            self.rho1 = r1
            self.rho2 = r2
            self.lfsr = lf
            self.swarm_idx = 0

            if self.variant == "new":
                self.state = "UPDATE_SWARM"
            else:
                self.state = "UPDATE_SWARM_PAR"

        elif state == "UPDATE_SWARM":
            # Versao nova: uma particula por ciclo.
            i = self.swarm_idx
            p, v = self.particle_update(i, low, high)
            self.particle_pos[i] = p
            self.particle_vel[i] = v

            if i == N_PARTICLES - 1:
                self.swarm_idx = 0
                self.state = "FINALIZE_SWARM"
            else:
                self.swarm_idx = i + 1

        elif state == "FINALIZE_SWARM":
            self.particle_pos[0] = self.pno_candidate
            self.particle_vel[0] = 0
            self.search_center = self.pno_candidate
            self.state = "APPLY_PARTICLE"

        elif state == "UPDATE_SWARM_PAR":
            # Versao original: todas as particulas num unico ciclo, com o
            # override da particula 0 no mesmo instante.
            new_pos = [0] * N_PARTICLES
            new_vel = [0] * N_PARTICLES

            for i in range(N_PARTICLES):
                new_pos[i], new_vel[i] = self.particle_update(i, low, high)

            self.particle_pos = new_pos
            self.particle_vel = new_vel
            self.particle_pos[0] = self.pno_candidate
            self.particle_vel[0] = 0
            self.search_center = self.pno_candidate
            self.state = "APPLY_PARTICLE"

        return self.store_valid

    def observe(self):
        return (
            self.duty_out,
            self.pno_candidate,
            self.gbest_pos,
            self.gbest_power,
            self.error_reg,
            self.delta_e_reg,
            self.fuzzy_delta,
        )


# ----------------------------------------------------------------------
# Estimulo (mesmos quatro regimes do tb_equivalence.vhd)
# ----------------------------------------------------------------------


def xorshift32(x: int) -> int:
    x &= 0xFFFFFFFF
    x ^= (x << 13) & 0xFFFFFFFF
    x ^= x >> 17
    x ^= (x << 5) & 0xFFFFFFFF

    return x & 0xFFFFFFFF


def to_s16(v: int) -> int:
    v &= 0xFFFF

    return v - 0x10000 if v >= 0x8000 else v


def to_s8(v: int) -> int:
    v &= 0xFF

    return v - 0x100 if v >= 0x80 else v


def make_stimulus(n: int, seed: int):
    out = []
    s = seed & 0xFFFFFFFF
    quart = n // 4

    for i in range(n):
        s = xorshift32(s)

        if i < quart:
            v = to_s16(s & 0xFFFF)
            c = to_s16((s >> 16) & 0xFFFF)
        elif i < 2 * quart:
            v = 4000 + (i - quart) * 7
            c = 12000 + vdiv(to_s8((s >> 16) & 0xFF), 4)
        elif i < 3 * quart:
            v = 8192 * ((s >> 8) & 0x3)
            c = to_s16((s >> 16) & 0xFFFF)
        else:
            v = to_s16(s & 0xFFFF)
            c = to_s16((s >> 16) & 0xFFFF)

        out.append((clamp(v, -32768, 32767), clamp(c, -32768, 32767)))

    return out


def run(variant: str, stim, g: dict, max_cycles_per_sample: int = 5000):
    ctrl = Controller(variant, g)
    obs = []

    for volt, curr in stim:
        cycles = 0

        while True:
            sv = ctrl.tick(curr, volt)
            cycles += 1

            if sv:
                break

            if cycles > max_cycles_per_sample:
                raise RuntimeError(f"{variant}: sem store_valid apos {cycles} ciclos")

        obs.append(ctrl.observe())

    return obs


FIELDS = [
    "duty",
    "control_duty",
    "gbest_duty",
    "gbest_power",
    "error",
    "delta_e",
    "fuzzy_delta",
]


def compare(a, b, label: str) -> int:
    bad = 0

    for i, (ra, rb) in enumerate(zip(a, b)):
        for k, (va, vb) in enumerate(zip(ra, rb)):
            if va != vb:
                bad += 1

                if bad <= 15:
                    print(
                        f"  [{label}] amostra {i} campo {FIELDS[k]}: "
                        f"novo={va} ref={vb}"
                    )

    return bad


def self_test_div_trunc() -> int:
    """div_trunc precisa ser bit a bit igual ao operador / do VHDL."""
    bad = 0

    for den, bits, lim in ((10000, ATTRACT_BITS, 6_502_500), (100, INERTIA_BITS, 130_560)):
        vals = list(range(-3000, 3001))
        vals += [lim, -lim, lim - 1, -lim + 1, 0, den, -den, den - 1, -(den - 1)]

        for num in vals:
            if abs(num) > lim:
                continue

            if div_trunc(num, den, bits) != vdiv(num, den):
                bad += 1
                print(f"  div_trunc({num},{den}) divergiu de vdiv")

    return bad


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=4000)
    parser.add_argument("--seed", type=int, default=305419896)
    args = parser.parse_args()

    total_bad = 0

    print("== 1. div_trunc contra o operador / do VHDL")
    bad = self_test_div_trunc()
    total_bad += bad
    print(f"   {'OK' if bad == 0 else str(bad) + ' divergencias'}")

    # Varias combinacoes de genericos, incluindo as que o experimento atual
    # nao exercita (deteccao de queda ligada, outros modos de centro).
    configs = [
        ("padrao do run_experiment.ps1", {}),
        ("defaults do VHDL", dict(
            W_PSO_G=50, C1_PSO_G=50, C2_PSO_G=40, RHO_MIN_G=53, RHO_MAX_G=56,
            DEADZONE_G=2, SEARCH_RADIUS_G=12, FOKKER_STEP_MAX_G=8,
            FUZZY_STEP_G=30, FUZZY_EDGE_G=90, DUTY_DIRECTION_G=-1,
            SEARCH_CENTER_MODE_G=1,
        )),
        ("deteccao de queda ligada", dict(
            ENABLE_CHANGE_DETECTION_G=1, DROP_PATIENCE_G=5,
            DROP_THRESHOLD_PERCENT_G=80,
        )),
        ("centro no P&O, janela larga", dict(
            SEARCH_CENTER_MODE_G=0, SEARCH_RADIUS_G=20, VEL_MIN_G=-30,
            VEL_MAX_G=30, MEMORY_HALF_LIFE_G=150, MAX_PBEST_AGE_G=250,
        )),
        ("settle longo, deadzone alta", dict(
            SETTLE_CYCLES=7, DEADZONE_G=5, FOKKER_STEP_MIN_G=2,
            FOKKER_STEP_MAX_G=12, FUZZY_STEP_G=20,
        )),
    ]

    stim = make_stimulus(args.samples, args.seed)
    print(f"\n== 2. Equivalencia sobre {args.samples} amostras por configuracao")

    for label, override in configs:
        g = dict(DEFAULT_GENERICS)
        g.update(override)

        try:
            obs_ref = run("ref", stim, g)
            obs_new = run("new", stim, g)
        except (RangeViolation, AssertionError) as exc:
            print(f"   [{label}] FALHOU: {exc}")
            total_bad += 1
            continue

        bad = compare(obs_new, obs_ref, label)
        total_bad += bad
        print(f"   [{label}] {'OK' if bad == 0 else str(bad) + ' divergencias'}")

    print()

    if total_bad == 0:
        print("RESULTADO: RTL refatorado equivalente ao original, sem estouro de faixa.")
        return 0

    print(f"RESULTADO: {total_bad} problemas encontrados.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
