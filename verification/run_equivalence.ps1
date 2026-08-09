# Roda o testbench de equivalencia no Questa/ModelSim.
#
# Compila o RTL refatorado (rlt/) e o RTL original preservado (verification/ref/)
# na mesma biblioteca work e compara os dois amostra a amostra.
#
# Uso, a partir da raiz do projeto:
#   .\verification\run_equivalence.ps1
#   .\verification\run_equivalence.ps1 -Samples 5000 -CleanWork

param(
    [string]$ProjectRoot = ".",
    [int]$Samples = 1200,
    [int]$Seed = 305419896,
    [switch]$CleanWork
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path $ProjectRoot
Push-Location $Root

try {
    $WorkDir = Join-Path $Root "work_equiv"

    if ($CleanWork -and (Test-Path $WorkDir)) {
        Remove-Item -Recurse -Force $WorkDir
    }

    if (-not (Test-Path $WorkDir)) {
        vlib $WorkDir
    }

    vmap work $WorkDir

    # RTL original, com entidades renomeadas para *_ref.
    $RefFiles = @(
        "verification/ref/hybrid_mppt_pkg_ref.vhd",
        "verification/ref/mppt_measurement_unit_ref.vhd",
        "verification/ref/mppt_fuzzy_ffp_unit_ref.vhd",
        "verification/ref/pso_search_window_unit_ref.vhd",
        "verification/ref/pso_random_coeff_unit_ref.vhd",
        "verification/ref/pso_particle_update_unit_ref.vhd",
        "verification/ref/pso_swarm_update_unit_ref.vhd",
        "verification/ref/pso_best_tracker_unit_ref.vhd",
        "verification/ref/hybrid_pso_fuzzy_mppt_ref.vhd",
        "verification/ref/mppt_top_ref.vhd"
    )

    # RTL refatorado.
    $NewFiles = @(
        "rlt/hybrid_mppt_pkg.vhd",
        "rlt/mppt_measurement_unit.vhd",
        "rlt/mppt_fuzzy_ffp_unit.vhd",
        "rlt/pso_search_window_unit.vhd",
        "rlt/pso_random_coeff_unit.vhd",
        "rlt/pso_particle_update_unit.vhd",
        "rlt/pso_best_tracker_unit.vhd",
        "rlt/hybrid_pso_fuzzy_mppt.vhd",
        "rlt/mppt_top.vhd",
        "rlt/mppt_fpga_top.vhd"
    )

    foreach ($File in ($RefFiles + $NewFiles + @("verification/tb_equivalence.vhd"))) {
        Write-Host "vcom $File"
        vcom -2008 -quiet $File
    }

    # Varias configuracoes de genericos, incluindo caminhos que o experimento
    # padrao nao exercita.
    $Configs = @(
        @{ Name = "padrao do run_experiment"; Args = @() },
        @{ Name = "defaults do VHDL"; Args = @(
            "-gW_PSO_G_TB=50", "-gC1_PSO_G_TB=50", "-gC2_PSO_G_TB=40",
            "-gRHO_MIN_G_TB=53", "-gRHO_MAX_G_TB=56", "-gDEADZONE_G_TB=2",
            "-gSEARCH_RADIUS_G_TB=12", "-gFOKKER_STEP_MAX_G_TB=8",
            "-gFUZZY_STEP_G_TB=30", "-gFUZZY_EDGE_G_TB=90",
            "-gDUTY_DIRECTION_G_TB=-1", "-gSEARCH_CENTER_MODE_G_TB=1") },
        @{ Name = "deteccao de queda ligada"; Args = @(
            "-gENABLE_CHANGE_DETECTION_G_TB=1", "-gDROP_PATIENCE_G_TB=5",
            "-gDROP_THRESHOLD_PERCENT_G_TB=80") },
        @{ Name = "centro no P&O, janela larga"; Args = @(
            "-gSEARCH_CENTER_MODE_G_TB=0", "-gSEARCH_RADIUS_G_TB=20",
            "-gVEL_MIN_G_TB=-30", "-gVEL_MAX_G_TB=30",
            "-gMEMORY_HALF_LIFE_G_TB=150", "-gMAX_PBEST_AGE_G_TB=250") },
        @{ Name = "settle longo, deadzone alta"; Args = @(
            "-gSETTLE_CYCLES_G=7", "-gDEADZONE_G_TB=5",
            "-gFOKKER_STEP_MIN_G_TB=2", "-gFOKKER_STEP_MAX_G_TB=12",
            "-gFUZZY_STEP_G_TB=20") }
    )

    $Failed = 0

    foreach ($Config in $Configs) {
        Write-Host ""
        Write-Host "=== $($Config.Name)"

        $VsimArgs = @(
            "-c", "-quiet",
            "-gN_SAMPLES=$Samples",
            "-gSEED_G=$Seed"
        ) + $Config.Args + @("work.tb_equivalence", "-do", "run -all; quit -f")

        & vsim @VsimArgs
        if ($LASTEXITCODE -ne 0) {
            $Failed++
            Write-Host "FALHOU: $($Config.Name)" -ForegroundColor Red
        }
    }

    Write-Host ""

    if ($Failed -eq 0) {
        Write-Host "Todas as configuracoes passaram." -ForegroundColor Green
    } else {
        Write-Host "$Failed configuracao(oes) falharam." -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}
