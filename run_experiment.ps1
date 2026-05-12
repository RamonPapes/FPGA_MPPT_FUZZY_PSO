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
    [switch]$CleanWork
)

$ErrorActionPreference = "Stop"

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
    vcom -2008 "hybrid_pso_fuzzy_mppt.vhd"
    vcom -2008 "tb_hybrid_pso_fuzzy_export.vhd"

    $DatasetFiles = Get-ChildItem -Path $PreprocessedPath -Filter "*_dataset.txt" | Sort-Object Name

    if ($DatasetFiles.Count -eq 0) {
        throw "Nenhum *_dataset.txt encontrado em: $PreprocessedPath"
    }

    foreach ($Dataset in $DatasetFiles) {
        $MonthName = [System.IO.Path]::GetFileNameWithoutExtension($Dataset.Name)
        $MonthName = $MonthName -replace "_dataset$", ""

        $ResultTxt = Join-Path $ResultsPath ($MonthName + "_results.txt")

        $DatasetArg = $Dataset.FullName.Replace("\", "/")
        $ResultArg  = $ResultTxt.Replace("\", "/")

        Write-Host ""
        Write-Host "=== Rodando simulacao para: $MonthName ==="

        vsim -c work.tb_hybrid_pso_fuzzy_export `
            -gDATASET_FILE="$DatasetArg" `
            -gRESULT_FILE="$ResultArg" `
            -do "run -all; quit -f"

        if (-not (Test-Path $ResultTxt)) {
            throw "Resultado nao foi gerado: $ResultTxt"
        }
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
