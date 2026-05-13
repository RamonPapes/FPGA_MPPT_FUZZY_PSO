param(
    [string]$ProjectRoot = ".",
    [string]$ArchiveDir = "archive",
    [string]$ResultsDir = "results",
    [string]$PreprocessedDir = "dados_pre_processados",
    [string]$PythonExe = "python",
    [string]$PowerColumn = "PVPCS_Active_Power",
    [string]$VoltageColumn = "MG-LV-MSB_AC_Voltage",
    [ValidateSet("W", "kW")]
    [string]$PowerUnit = "kW",
    [int]$MaxParallel = 4,
    [switch]$CleanWork
)

$ErrorActionPreference = "Stop"

if ($MaxParallel -lt 1) {
    throw "MaxParallel deve ser maior ou igual a 1."
}

$ProjectRoot = (Resolve-Path $ProjectRoot).Path
$ArchivePath = Join-Path $ProjectRoot $ArchiveDir
$ResultsPath = Join-Path $ProjectRoot $ResultsDir
$PreprocessedPath = Join-Path $ProjectRoot $PreprocessedDir

$PkgFile = Join-Path $ProjectRoot "hybrid_mppt_pkg.vhd"
$TopFile = Join-Path $ProjectRoot "hybrid_pso_fuzzy_mppt.vhd"
$TbFile  = Join-Path $ProjectRoot "tb_hybrid_pso_fuzzy_export.vhd"

$PreprocessScript = Join-Path $ProjectRoot "pre_process_data.py"
$MetricsScript = Join-Path $ProjectRoot "gen_results.py"

if (-not (Test-Path $ArchivePath)) {
    throw "Pasta archive nao encontrada: $ArchivePath"
}

if (-not (Test-Path $PkgFile)) {
    throw "Arquivo nao encontrado: $PkgFile"
}

if (-not (Test-Path $TopFile)) {
    throw "Arquivo nao encontrado: $TopFile"
}

if (-not (Test-Path $TbFile)) {
    throw "Arquivo nao encontrado: $TbFile"
}

if (-not (Test-Path $PreprocessScript)) {
    throw "Script Python de pre-processamento nao encontrado: $PreprocessScript"
}

if (-not (Test-Path $MetricsScript)) {
    throw "Script Python de metricas nao encontrado: $MetricsScript"
}

New-Item -ItemType Directory -Force -Path $ResultsPath | Out-Null
New-Item -ItemType Directory -Force -Path $PreprocessedPath | Out-Null

if ($CleanWork -and (Test-Path (Join-Path $ProjectRoot "work"))) {
    Remove-Item -Recurse -Force (Join-Path $ProjectRoot "work")
}

Push-Location $ProjectRoot

try {
    Write-Host ""
    Write-Host "=== Pre-processando dados em archive ==="

    & $PythonExe $PreprocessScript `
        --archive-dir $ArchivePath `
        --output-dir $PreprocessedPath `
        --power-col $PowerColumn `
        --voltage-col $VoltageColumn `
        --power-unit $PowerUnit

    Write-Host ""
    Write-Host "=== Compilando projeto VHDL ==="

    if (-not (Test-Path (Join-Path $ProjectRoot "work"))) {
        vlib work
    }

    vcom -2008 "hybrid_mppt_pkg.vhd"
    vcom -2008 "mppt_measurement_unit.vhd"
    vcom -2008 "mppt_fuzzy_ffp_unit.vhd"
    vcom -2008 "pso_particle_update_unit.vhd"
    vcom -2008 "hybrid_pso_fuzzy_mppt.vhd"
    vcom -2008 "tb_hybrid_pso_fuzzy_export.vhd"

    $DatasetFiles = Get-ChildItem -Path $PreprocessedPath -Filter "*_dataset.txt" | Sort-Object Name

    if ($DatasetFiles.Count -eq 0) {
        throw "Nenhum *_dataset.txt encontrado em: $PreprocessedPath"
    }

    Write-Host ""
    Write-Host "=== Rodando simulacoes em paralelo: $MaxParallel por vez ==="

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
                    if ($Item.Status -ne "OK") {
                        $Failures += $Item
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
                $WlfArgJob
            )

            Set-Location $ProjectRootJob

            try {
                & vsim `
                    -c work.tb_hybrid_pso_fuzzy_export `
                    -wlf $WlfArgJob `
                    -l $LogArgJob `
                    "-gDATASET_FILE=$DatasetArgJob" `
                    "-gRESULT_FILE=$ResultArgJob" `
                    -do "run -all; quit -f"

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
        } -ArgumentList $ProjectRoot, $MonthName, $DatasetArg, $ResultArg, $LogArg, $WlfArg

        $Jobs += $Job
    }

    while ($Jobs.Count -gt 0) {
        $Done = Wait-Job -Job $Jobs -Any

        foreach ($Job in @($Done)) {
            $Output = Receive-Job -Job $Job

            foreach ($Item in $Output) {
                if ($Item.Status -eq "OK") {
                    Write-Host "OK: $($Item.Month)"
                }
                else {
                    Write-Host "ERRO: $($Item.Month) -> $($Item.Message)"
                    Write-Host "Log: $($Item.Log)"
                    $Failures += $Item
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
    Write-Host "Processo finalizado."
    Write-Host "Dados pre-processados: $PreprocessedPath"
    Write-Host "Resultados: $ResultsPath"
}
finally {
    Pop-Location
}
