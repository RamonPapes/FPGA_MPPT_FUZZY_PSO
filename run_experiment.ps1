param(
    [string]$ProjectRoot = ".",
    [string]$ArchiveDir = "archive",
    [string]$ScriptsDir = "scripts",
    [string]$ResultsDir = "results",
    [string]$PreprocessedDir = "dados_pre_processados",
    [string]$PlotsDir = "graficos_uteis",
    [string]$PythonExe = "python",
    [string]$PowerColumn = "PVPCS_Active_Power",
    [string]$VoltageColumn = "MG-LV-MSB_AC_Voltage",
    [ValidateSet("W", "kW")]
    [string]$PowerUnit = "kW",
    [ValidateSet("q1.15-normalized", "linear")]
    [string]$CurrentFormat = "q1.15-normalized",
    [double]$CurrentBaseAmps = 0.0,
    [double]$CurrentQ15Scale = 32767.0,
    [string]$PlotDayResultFile = "Apr_2023_results.txt",
    [int]$PlotTargetDate = 20230415,
    [int]$MaxParallel = 1,
    [string]$OptimizationDir = "optimization_runs",
    [string]$OptimizationDataset = "",
    [ValidateSet("stage1", "stage2", "both")]
    [string]$OptimizationStage = "both",
    [int]$OptimizationDays = 5,
    [int]$OptimizationStage1Trials = 20,
    [int]$OptimizationStage2TopK = 3,
    [int]$OptimizationStage2TrialsPerBase = 8,
    [int]$OptimizationMaxWorkers = 1,
    [int]$OptimizationSeed = 42,
    [switch]$SkipOptimization,
    [switch]$SkipCalcError,
    [switch]$CleanWork,

    [int]$SETTLE_CYCLES_G = 1,
    [int]$W_PSO_G_TB = 70,
    [int]$C1_PSO_G_TB = 60,
    [int]$C2_PSO_G_TB = 60,
    [int]$RHO_MIN_G_TB = 55,
    [int]$RHO_MAX_G_TB = 65,
    [int]$VEL_MIN_G_TB = -20,
    [int]$VEL_MAX_G_TB = 20,
    [int]$DEADZONE_G_TB = 1,
    [int]$SEARCH_RADIUS_G_TB = 10,
    [int]$FOKKER_STEP_MIN_G_TB = 1,
    [int]$FOKKER_STEP_MAX_G_TB = 4,
    [int]$FUZZY_STEP_G_TB = 40,
    [int]$FUZZY_EDGE_G_TB = 100,
    [int]$POWER_SCALE_DEN_G_TB = 65536,
    [int]$ERROR_GAIN_G_TB = 1,
    [int]$DELTA_V_MIN_G_TB = 16,
    [int]$DUTY_DIRECTION_G_TB = 1,
    [int]$SEARCH_CENTER_MODE_G_TB = 2,
    [int]$RESET_ON_DATE_CHANGE_G_TB = 0,
    [int]$MEMORY_HALF_LIFE_G_TB = 300,
    [int]$MAX_PBEST_AGE_G_TB = 500,
    [int]$ENABLE_CHANGE_DETECTION_G_TB = 0,
    [int]$DROP_THRESHOLD_PERCENT_G_TB = 70,
    [int]$DROP_PATIENCE_G_TB = 30
)

$ErrorActionPreference = "Stop"

if ($MaxParallel -lt 1) {
    throw "MaxParallel deve ser maior ou igual a 1."
}

function Resolve-FromBase {
    param(
        [string]$BasePath,
        [string]$PathText
    )

    if ([System.IO.Path]::IsPathRooted($PathText)) {
        return $PathText
    }

    return (Join-Path $BasePath $PathText)
}

function Set-IntegerParameterFromRow {
    param(
        [object]$Row,
        [string]$Name
    )

    if ($Row.PSObject.Properties.Name -notcontains $Name) {
        return
    }

    $ValueText = [string]$Row.$Name

    if ([string]::IsNullOrWhiteSpace($ValueText)) {
        return
    }

    $Culture = [System.Globalization.CultureInfo]::InvariantCulture
    $Value = [int][Math]::Round([double]::Parse($ValueText, $Culture))
    Set-Variable -Name $Name -Scope Script -Value $Value
}

$TunableGenericKeys = @(
    "SETTLE_CYCLES_G",
    "W_PSO_G_TB",
    "C1_PSO_G_TB",
    "C2_PSO_G_TB",
    "RHO_MIN_G_TB",
    "RHO_MAX_G_TB",
    "VEL_MIN_G_TB",
    "VEL_MAX_G_TB",
    "DEADZONE_G_TB",
    "SEARCH_RADIUS_G_TB",
    "FOKKER_STEP_MIN_G_TB",
    "FOKKER_STEP_MAX_G_TB",
    "FUZZY_STEP_G_TB",
    "FUZZY_EDGE_G_TB",
    "POWER_SCALE_DEN_G_TB",
    "ERROR_GAIN_G_TB",
    "DELTA_V_MIN_G_TB",
    "DUTY_DIRECTION_G_TB",
    "SEARCH_CENTER_MODE_G_TB",
    "RESET_ON_DATE_CHANGE_G_TB",
    "MEMORY_HALF_LIFE_G_TB",
    "MAX_PBEST_AGE_G_TB",
    "ENABLE_CHANGE_DETECTION_G_TB",
    "DROP_THRESHOLD_PERCENT_G_TB",
    "DROP_PATIENCE_G_TB"
)

$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$ArchivePath = Resolve-FromBase $ProjectRoot $ArchiveDir
$ScriptsPath = Resolve-FromBase $ProjectRoot $ScriptsDir
$ResultsPath = Resolve-FromBase $ProjectRoot $ResultsDir
$PreprocessedPath = Resolve-FromBase $ResultsPath $PreprocessedDir
$PlotsPath = Resolve-FromBase $ResultsPath $PlotsDir
$OptimizationPath = Resolve-FromBase $ResultsPath $OptimizationDir
$RtlPath = Join-Path $ProjectRoot "rlt"

$VhdlFiles = @(
    "hybrid_mppt_pkg.vhd",
    "mppt_measurement_unit.vhd",
    "mppt_fuzzy_ffp_unit.vhd",
    "pso_search_window_unit.vhd",
    "pso_random_coeff_unit.vhd",
    "pso_particle_update_unit.vhd",
    "pso_swarm_update_unit.vhd",
    "pso_best_tracker_unit.vhd",
    "hybrid_pso_fuzzy_mppt.vhd",
    "mppt_top.vhd",
    "tb_hybrid_pso_fuzzy_export.vhd"
)

$PreprocessScript = Join-Path $ScriptsPath "pre_process_data.py"
$MetricsScript = Join-Path $ScriptsPath "gen_results.py"
$PlotsScript = Join-Path $ScriptsPath "gen_plots.py"
$OptimizerScript = Join-Path $ScriptsPath "optimize_hyperparameters.py"
$CalcErrorScript = Join-Path $ScriptsPath "calc_error.py"

if (-not (Test-Path $ArchivePath)) {
    throw "Pasta archive nao encontrada: $ArchivePath"
}

foreach ($VhdlFile in $VhdlFiles) {
    $VhdlPath = Join-Path $RtlPath $VhdlFile

    if (-not (Test-Path $VhdlPath)) {
        throw "Arquivo VHDL nao encontrado: $VhdlPath"
    }
}

if (-not (Test-Path $PreprocessScript)) {
    throw "Script Python de pre-processamento nao encontrado: $PreprocessScript"
}

if (-not (Test-Path $MetricsScript)) {
    throw "Script Python de metricas nao encontrado: $MetricsScript"
}

if (-not (Test-Path $PlotsScript)) {
    throw "Script Python de graficos nao encontrado: $PlotsScript"
}

if (-not (Test-Path $OptimizerScript)) {
    throw "Script Python de otimizacao nao encontrado: $OptimizerScript"
}

if (-not (Test-Path $CalcErrorScript)) {
    throw "Script Python de analise de erro nao encontrado: $CalcErrorScript"
}

New-Item -ItemType Directory -Force -Path $ResultsPath | Out-Null
New-Item -ItemType Directory -Force -Path $PreprocessedPath | Out-Null
New-Item -ItemType Directory -Force -Path $PlotsPath | Out-Null
New-Item -ItemType Directory -Force -Path $OptimizationPath | Out-Null

if ($CleanWork -and (Test-Path (Join-Path $ProjectRoot "work"))) {
    Remove-Item -Recurse -Force (Join-Path $ProjectRoot "work")
}

Push-Location $ProjectRoot

try {
    Write-Host ""
    Write-Host "=== Hiperparametros usados ==="
    Write-Host "W=$W_PSO_G_TB C1=$C1_PSO_G_TB C2=$C2_PSO_G_TB"
    Write-Host "DEADZONE=$DEADZONE_G_TB FOKKER_STEP_MIN=$FOKKER_STEP_MIN_G_TB FOKKER_STEP_MAX=$FOKKER_STEP_MAX_G_TB"
    Write-Host "FUZZY_STEP=$FUZZY_STEP_G_TB FUZZY_EDGE=$FUZZY_EDGE_G_TB"
    Write-Host "RHO_MIN=$RHO_MIN_G_TB RHO_MAX=$RHO_MAX_G_TB"
    Write-Host "VEL_MIN=$VEL_MIN_G_TB VEL_MAX=$VEL_MAX_G_TB"
    Write-Host "SEARCH_CENTER_MODE=$SEARCH_CENTER_MODE_G_TB SEARCH_RADIUS=$SEARCH_RADIUS_G_TB"
    Write-Host "DUTY_DIRECTION=$DUTY_DIRECTION_G_TB POWER_SCALE_DEN=$POWER_SCALE_DEN_G_TB"
    Write-Host "ERROR_GAIN=$ERROR_GAIN_G_TB DELTA_V_MIN=$DELTA_V_MIN_G_TB"
    Write-Host "RESET_ON_DATE_CHANGE=$RESET_ON_DATE_CHANGE_G_TB"
    Write-Host "MEMORY_HALF_LIFE=$MEMORY_HALF_LIFE_G_TB MAX_PBEST_AGE=$MAX_PBEST_AGE_G_TB"
    Write-Host "ENABLE_CHANGE_DETECTION=$ENABLE_CHANGE_DETECTION_G_TB DROP_THRESHOLD_PERCENT=$DROP_THRESHOLD_PERCENT_G_TB DROP_PATIENCE=$DROP_PATIENCE_G_TB"
    Write-Host "CURRENT_FORMAT=$CurrentFormat CURRENT_BASE_AMPS=$CurrentBaseAmps CURRENT_Q15_SCALE=$CurrentQ15Scale"

    Write-Host ""
    Write-Host "=== Pre-processando dados em archive ==="

    & $PythonExe $PreprocessScript `
        --archive-dir $ArchivePath `
        --output-dir $PreprocessedPath `
        --power-col $PowerColumn `
        --voltage-col $VoltageColumn `
        --power-unit $PowerUnit `
        --current-format $CurrentFormat `
        --current-base-amps $CurrentBaseAmps `
        --current-q15-scale $CurrentQ15Scale

    Write-Host ""
    Write-Host "=== Compilando projeto VHDL ==="

    if (-not (Test-Path (Join-Path $ProjectRoot "work"))) {
        vlib work
    }

    foreach ($VhdlFile in $VhdlFiles) {
        vcom -2008 (Join-Path "rlt" $VhdlFile)
    }

    $DatasetFiles = Get-ChildItem -Path $PreprocessedPath -Filter "*_dataset.txt" | Sort-Object Name

    if ($DatasetFiles.Count -eq 0) {
        throw "Nenhum *_dataset.txt encontrado em: $PreprocessedPath"
    }

    if (-not $SkipOptimization) {
        Write-Host ""
        Write-Host "=== Otimizando hiperparametros ==="

        if ([string]::IsNullOrWhiteSpace($OptimizationDataset)) {
            $PreferredDataset = $DatasetFiles | Where-Object { $_.Name -eq "Apr_2023_dataset.txt" } | Select-Object -First 1

            if ($null -eq $PreferredDataset) {
                $PreferredDataset = $DatasetFiles | Select-Object -First 1
            }

            $OptimizationDatasetPath = $PreferredDataset.FullName
        }
        else {
            $OptimizationDatasetPath = Resolve-FromBase $ProjectRoot $OptimizationDataset
        }

        if (-not (Test-Path $OptimizationDatasetPath)) {
            throw "Dataset de otimizacao nao encontrado: $OptimizationDatasetPath"
        }

        Write-Host "Dataset de otimizacao: $OptimizationDatasetPath"
        Write-Host "Saida da otimizacao: $OptimizationPath"
        Write-Host "Stage=$OptimizationStage Dias=$OptimizationDays Stage1Trials=$OptimizationStage1Trials Stage2TopK=$OptimizationStage2TopK Stage2TrialsPorBase=$OptimizationStage2TrialsPerBase"

        & $PythonExe $OptimizerScript `
            --project-dir $ProjectRoot `
            --dataset $OptimizationDatasetPath `
            --out-dir $OptimizationPath `
            --n-days $OptimizationDays `
            --stage $OptimizationStage `
            --stage1-trials $OptimizationStage1Trials `
            --stage2-top-k $OptimizationStage2TopK `
            --stage2-trials-per-base $OptimizationStage2TrialsPerBase `
            --seed $OptimizationSeed `
            --max-workers $OptimizationMaxWorkers

        if ($LASTEXITCODE -ne 0) {
            throw "Otimizacao terminou com codigo $LASTEXITCODE."
        }

        $BestFiles = @(
            (Join-Path $OptimizationPath "optimization_final_best.csv"),
            (Join-Path $OptimizationPath "stage2\stage2_best.csv"),
            (Join-Path $OptimizationPath "stage1\stage1_best.csv")
        )

        $BestFile = $BestFiles | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ([string]::IsNullOrWhiteSpace($BestFile)) {
            throw "Nenhum arquivo de melhores hiperparametros foi encontrado em: $OptimizationPath"
        }

        $BestRow = Import-Csv $BestFile | Select-Object -First 1

        if ($null -eq $BestRow) {
            throw "Arquivo de melhores hiperparametros vazio: $BestFile"
        }

        foreach ($Key in $TunableGenericKeys) {
            Set-IntegerParameterFromRow -Row $BestRow -Name $Key
        }

        Write-Host ""
        Write-Host "=== Melhores hiperparametros aplicados ==="
        Write-Host "Arquivo: $BestFile"
        Write-Host "Score=$($BestRow.score)"
        Write-Host "W=$W_PSO_G_TB C1=$C1_PSO_G_TB C2=$C2_PSO_G_TB"
        Write-Host "DEADZONE=$DEADZONE_G_TB FOKKER_STEP_MIN=$FOKKER_STEP_MIN_G_TB FOKKER_STEP_MAX=$FOKKER_STEP_MAX_G_TB"
        Write-Host "FUZZY_STEP=$FUZZY_STEP_G_TB FUZZY_EDGE=$FUZZY_EDGE_G_TB"
        Write-Host "RHO_MIN=$RHO_MIN_G_TB RHO_MAX=$RHO_MAX_G_TB"
        Write-Host "VEL_MIN=$VEL_MIN_G_TB VEL_MAX=$VEL_MAX_G_TB"
        Write-Host "SEARCH_CENTER_MODE=$SEARCH_CENTER_MODE_G_TB SEARCH_RADIUS=$SEARCH_RADIUS_G_TB"
        Write-Host "DUTY_DIRECTION=$DUTY_DIRECTION_G_TB POWER_SCALE_DEN=$POWER_SCALE_DEN_G_TB"
        Write-Host "ERROR_GAIN=$ERROR_GAIN_G_TB DELTA_V_MIN=$DELTA_V_MIN_G_TB"
        Write-Host "RESET_ON_DATE_CHANGE=$RESET_ON_DATE_CHANGE_G_TB"
        Write-Host "MEMORY_HALF_LIFE=$MEMORY_HALF_LIFE_G_TB MAX_PBEST_AGE=$MAX_PBEST_AGE_G_TB"
        Write-Host "ENABLE_CHANGE_DETECTION=$ENABLE_CHANGE_DETECTION_G_TB DROP_THRESHOLD_PERCENT=$DROP_THRESHOLD_PERCENT_G_TB DROP_PATIENCE=$DROP_PATIENCE_G_TB"
    }
    else {
        Write-Host ""
        Write-Host "=== Otimizacao pulada: usando hiperparametros informados ==="
    }

    Write-Host ""
    if ($MaxParallel -eq 1) {
        Write-Host "=== Rodando simulacoes sequencialmente ==="
    }
    else {
        Write-Host "=== Rodando simulacoes em paralelo: $MaxParallel por vez ==="
        Write-Host "Aviso: licencas uncounted node-locked do Questa/ModelSim normalmente permitem apenas uma sessao por vez."
        Write-Host "Se aparecer erro de checkout de licenca, rode novamente com -MaxParallel 1."
    }

    $Jobs = @()
    $Failures = @()

    foreach ($Dataset in $DatasetFiles) {
        $MonthName = [System.IO.Path]::GetFileNameWithoutExtension($Dataset.Name)
        $MonthName = $MonthName -replace "_dataset$", ""

        $ResultTxt = Join-Path $ResultsPath ($MonthName + "_results.txt")
        $LogTxt    = Join-Path $ResultsPath ($MonthName + "_vsim.log")
        $WlfFile   = Join-Path $ResultsPath ($MonthName + ".wlf")

        if (Test-Path $ResultTxt) {
            Remove-Item -Force $ResultTxt
        }

        if (Test-Path $LogTxt) {
            Remove-Item -Force $LogTxt
        }

        if (Test-Path $WlfFile) {
            Remove-Item -Force $WlfFile
        }

        $DatasetArg = $Dataset.FullName.Replace("\", "/")
        $ResultArg  = $ResultTxt.Replace("\", "/")
        $LogArg     = $LogTxt.Replace("\", "/")
        $WlfArg     = $WlfFile.Replace("\", "/")

        while (($Jobs | Where-Object { $_.State -eq "Running" }).Count -ge $MaxParallel) {
            $Done = Wait-Job -Job $Jobs -Any

            foreach ($Job in @($Done)) {
                $Output = Receive-Job -Job $Job

                foreach ($Item in $Output) {
                    if ($Item -is [pscustomobject] -and $Item.PSObject.Properties.Name -contains "Status") {
                        if ($Item.Status -eq "OK") {
                            Write-Host "OK: $($Item.Month)"
                        }
                        else {
                            Write-Host "ERRO: $($Item.Month) -> $($Item.Message)"
                            Write-Host "Log: $($Item.Log)"
                            $Failures += $Item
                        }
                    }
                }

                Remove-Job -Job $Job
                $Jobs = @($Jobs | Where-Object { $_.Id -ne $Job.Id })
            }
        }

        Write-Host "Spawn vsim: $MonthName"

        $Job = Start-Job -Name $MonthName -ScriptBlock {
            param(
                $ProjectRootJob,
                $MonthNameJob,
                $DatasetArgJob,
                $ResultArgJob,
                $LogArgJob,
                $WlfArgJob,
                $SETTLE_CYCLES_G_Job,
                $W_PSO_G_TB_Job,
                $C1_PSO_G_TB_Job,
                $C2_PSO_G_TB_Job,
                $RHO_MIN_G_TB_Job,
                $RHO_MAX_G_TB_Job,
                $VEL_MIN_G_TB_Job,
                $VEL_MAX_G_TB_Job,
                $DEADZONE_G_TB_Job,
                $SEARCH_RADIUS_G_TB_Job,
                $FOKKER_STEP_MIN_G_TB_Job,
                $FOKKER_STEP_MAX_G_TB_Job,
                $FUZZY_STEP_G_TB_Job,
                $FUZZY_EDGE_G_TB_Job,
                $POWER_SCALE_DEN_G_TB_Job,
                $ERROR_GAIN_G_TB_Job,
                $DELTA_V_MIN_G_TB_Job,
                $DUTY_DIRECTION_G_TB_Job,
                $SEARCH_CENTER_MODE_G_TB_Job,
                $RESET_ON_DATE_CHANGE_G_TB_Job,
                $MEMORY_HALF_LIFE_G_TB_Job,
                $MAX_PBEST_AGE_G_TB_Job,
                $ENABLE_CHANGE_DETECTION_G_TB_Job,
                $DROP_THRESHOLD_PERCENT_G_TB_Job,
                $DROP_PATIENCE_G_TB_Job
            )

            Set-Location $ProjectRootJob

            try {
                & vsim `
                    -c work.tb_hybrid_pso_fuzzy_export `
                    -wlf $WlfArgJob `
                    -l $LogArgJob `
                    "-gDATASET_FILE=$DatasetArgJob" `
                    "-gRESULT_FILE=$ResultArgJob" `
                    "-gSETTLE_CYCLES_G=$SETTLE_CYCLES_G_Job" `
                    "-gW_PSO_G_TB=$W_PSO_G_TB_Job" `
                    "-gC1_PSO_G_TB=$C1_PSO_G_TB_Job" `
                    "-gC2_PSO_G_TB=$C2_PSO_G_TB_Job" `
                    "-gRHO_MIN_G_TB=$RHO_MIN_G_TB_Job" `
                    "-gRHO_MAX_G_TB=$RHO_MAX_G_TB_Job" `
                    "-gVEL_MIN_G_TB=$VEL_MIN_G_TB_Job" `
                    "-gVEL_MAX_G_TB=$VEL_MAX_G_TB_Job" `
                    "-gDEADZONE_G_TB=$DEADZONE_G_TB_Job" `
                    "-gSEARCH_RADIUS_G_TB=$SEARCH_RADIUS_G_TB_Job" `
                    "-gFOKKER_STEP_MIN_G_TB=$FOKKER_STEP_MIN_G_TB_Job" `
                    "-gFOKKER_STEP_MAX_G_TB=$FOKKER_STEP_MAX_G_TB_Job" `
                    "-gFUZZY_STEP_G_TB=$FUZZY_STEP_G_TB_Job" `
                    "-gFUZZY_EDGE_G_TB=$FUZZY_EDGE_G_TB_Job" `
                    "-gPOWER_SCALE_DEN_G_TB=$POWER_SCALE_DEN_G_TB_Job" `
                    "-gERROR_GAIN_G_TB=$ERROR_GAIN_G_TB_Job" `
                    "-gDELTA_V_MIN_G_TB=$DELTA_V_MIN_G_TB_Job" `
                    "-gDUTY_DIRECTION_G_TB=$DUTY_DIRECTION_G_TB_Job" `
                    "-gSEARCH_CENTER_MODE_G_TB=$SEARCH_CENTER_MODE_G_TB_Job" `
                    "-gRESET_ON_DATE_CHANGE_G_TB=$RESET_ON_DATE_CHANGE_G_TB_Job" `
                    "-gMEMORY_HALF_LIFE_G_TB=$MEMORY_HALF_LIFE_G_TB_Job" `
                    "-gMAX_PBEST_AGE_G_TB=$MAX_PBEST_AGE_G_TB_Job" `
                    "-gENABLE_CHANGE_DETECTION_G_TB=$ENABLE_CHANGE_DETECTION_G_TB_Job" `
                    "-gDROP_THRESHOLD_PERCENT_G_TB=$DROP_THRESHOLD_PERCENT_G_TB_Job" `
                    "-gDROP_PATIENCE_G_TB=$DROP_PATIENCE_G_TB_Job" `
                    -do "run -all; quit -f" *> $null

                $ExitCode = $LASTEXITCODE

                if ($ExitCode -ne 0) {
                    [PSCustomObject]@{
                        Month = $MonthNameJob
                        Status = "ERROR"
                        ExitCode = $ExitCode
                        Result = $ResultArgJob
                        Log = $LogArgJob
                        Message = "vsim terminou com codigo $ExitCode"
                    }
                    return
                }

                if (-not (Test-Path $ResultArgJob)) {
                    [PSCustomObject]@{
                        Month = $MonthNameJob
                        Status = "ERROR"
                        ExitCode = 999
                        Result = $ResultArgJob
                        Log = $LogArgJob
                        Message = "Arquivo de resultado nao foi gerado"
                    }
                    return
                }

                [PSCustomObject]@{
                    Month = $MonthNameJob
                    Status = "OK"
                    ExitCode = 0
                    Result = $ResultArgJob
                    Log = $LogArgJob
                    Message = "Simulacao concluida"
                }
            }
            catch {
                [PSCustomObject]@{
                    Month = $MonthNameJob
                    Status = "ERROR"
                    ExitCode = 998
                    Result = $ResultArgJob
                    Log = $LogArgJob
                    Message = $_.Exception.Message
                }
            }
        } -ArgumentList `
            $ProjectRoot, `
            $MonthName, `
            $DatasetArg, `
            $ResultArg, `
            $LogArg, `
            $WlfArg, `
            $SETTLE_CYCLES_G, `
            $W_PSO_G_TB, `
            $C1_PSO_G_TB, `
            $C2_PSO_G_TB, `
            $RHO_MIN_G_TB, `
            $RHO_MAX_G_TB, `
            $VEL_MIN_G_TB, `
            $VEL_MAX_G_TB, `
            $DEADZONE_G_TB, `
            $SEARCH_RADIUS_G_TB, `
            $FOKKER_STEP_MIN_G_TB, `
            $FOKKER_STEP_MAX_G_TB, `
            $FUZZY_STEP_G_TB, `
            $FUZZY_EDGE_G_TB, `
            $POWER_SCALE_DEN_G_TB, `
            $ERROR_GAIN_G_TB, `
            $DELTA_V_MIN_G_TB, `
            $DUTY_DIRECTION_G_TB, `
            $SEARCH_CENTER_MODE_G_TB, `
            $RESET_ON_DATE_CHANGE_G_TB, `
            $MEMORY_HALF_LIFE_G_TB, `
            $MAX_PBEST_AGE_G_TB, `
            $ENABLE_CHANGE_DETECTION_G_TB, `
            $DROP_THRESHOLD_PERCENT_G_TB, `
            $DROP_PATIENCE_G_TB

        $Jobs += $Job
    }

    while ($Jobs.Count -gt 0) {
        $Done = Wait-Job -Job $Jobs -Any

        foreach ($Job in @($Done)) {
            $Output = Receive-Job -Job $Job

            foreach ($Item in $Output) {
                if ($Item -is [pscustomobject] -and $Item.PSObject.Properties.Name -contains "Status") {
                    if ($Item.Status -eq "OK") {
                        Write-Host "OK: $($Item.Month)"
                    }
                    else {
                        Write-Host "ERRO: $($Item.Month) -> $($Item.Message)"
                        Write-Host "Log: $($Item.Log)"
                        $Failures += $Item
                    }
                }
            }

            Remove-Job -Job $Job
            $Jobs = @($Jobs | Where-Object { $_.Id -ne $Job.Id })
        }
    }

    if ($Failures.Count -gt 0) {
        Write-Host ""
        Write-Host "=== Falhas encontradas ==="

        foreach ($Failure in $Failures) {
            Write-Host "$($Failure.Month): $($Failure.Message)"
            Write-Host "Log: $($Failure.Log)"
        }

        throw "$($Failures.Count) simulacao(oes) falharam."
    }

    Write-Host ""
    Write-Host "=== Calculando metricas ==="

    & $PythonExe $MetricsScript --results-dir $ResultsPath

    Write-Host ""
    Write-Host "=== Gerando graficos ==="

    & $PythonExe $PlotsScript `
        --results-dir $ResultsPath `
        --output-dir $PlotsPath `
        --day-result-file $PlotDayResultFile `
        --target-date $PlotTargetDate

    if (-not $SkipCalcError) {
        Write-Host ""
        Write-Host "=== Calculando analise de escalonamento do erro ==="

        & $PythonExe $CalcErrorScript `
            --dataset $PreprocessedPath `
            --output (Join-Path $ResultsPath "error_scaling_analysis.csv")

        if ($LASTEXITCODE -ne 0) {
            throw "Analise de erro terminou com codigo $LASTEXITCODE."
        }
    }
    else {
        Write-Host ""
        Write-Host "=== Analise de erro pulada ==="
    }

    Write-Host ""
    Write-Host "Processo finalizado."
    Write-Host "Dados pre-processados: $PreprocessedPath"
    Write-Host "Resultados: $ResultsPath"
    Write-Host "Graficos: $PlotsPath"
    Write-Host "Otimizacao: $OptimizationPath"
}
finally {
    Pop-Location
}
