from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def normalize_name(name: str) -> str:
    return name.replace("\ufeff", "").strip()

def parse_number(value: str) -> float | None:
    if value is None:
        return None

    text = str(value).strip()

    if not text:
        return None

    text = text.replace('"', "").replace("'", "").strip()

    if "," in text and "." not in text:
        text = text.replace(",", ".")
    elif "," in text and "." in text:
        text = text.replace(",", "")

    try:
        number = float(text)
    except ValueError:
        return None

    if math.isnan(number) or math.isinf(number):
        return None

    return number


def clamp_int16(value: int) -> int:
    if value < -32768:
        return -32768
    if value > 32767:
        return 32767
    return value


def detect_dialect(csv_path: Path) -> csv.Dialect:
    sample = csv_path.read_text(encoding="utf-8-sig", errors="ignore")[:4096]

    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        return csv.excel


def convert_csv(
    csv_path: Path,
    output_path: Path,
    power_col: str,
    voltage_col: str,
    power_unit: str,
    voltage_scale: float,
    current_scale: float,
    min_voltage: float,
    keep_power_sign: bool,
) -> dict[str, int | str]:
    dialect = detect_dialect(csv_path)

    total_rows = 0
    valid_rows = 0
    skipped_rows = 0

    output_lines: list[str] = []

    with csv_path.open("r", encoding="utf-8-sig", errors="ignore", newline="") as f:
        reader = csv.DictReader(f, dialect=dialect)

        if reader.fieldnames is None:
            raise ValueError(f"Arquivo sem cabecalho: {csv_path}")

        original_fields = reader.fieldnames
        fields = [normalize_name(field) for field in original_fields]

        field_map = {
            normalize_name(original): normalized
            for original, normalized in zip(original_fields, fields)
        }

        normalized_rows = []
        for row in reader:
            normalized_row = {}
            for original_name, value in row.items():
                if original_name is None:
                    continue
                normalized_row[field_map[original_name]] = value
            normalized_rows.append(normalized_row)

        if power_col not in fields:
            raise ValueError(
                f"Coluna de potencia nao encontrada em {csv_path.name}: {power_col}. "
                f"Colunas disponiveis: {fields}"
            )

        if voltage_col not in fields:
            raise ValueError(
                f"Coluna de tensao nao encontrada em {csv_path.name}: {voltage_col}. "
                f"Colunas disponiveis: {fields}"
            )

        for row in normalized_rows:
            total_rows += 1

            power = parse_number(row.get(power_col))
            voltage = parse_number(row.get(voltage_col))

            if power is None or voltage is None:
                skipped_rows += 1
                continue

            if abs(voltage) < min_voltage:
                skipped_rows += 1
                continue

            if not keep_power_sign:
                power = abs(power)

            if power_unit.lower() == "kw":
                power_watts = power * 1000.0
            elif power_unit.lower() == "w":
                power_watts = power
            else:
                raise ValueError("power_unit deve ser 'W' ou 'kW'.")

            current = power_watts / voltage

            voltage_int = clamp_int16(int(round(voltage * voltage_scale)))
            current_int = clamp_int16(int(round(current * current_scale)))

            output_lines.append(f"{voltage_int} {current_int}")
            valid_rows += 1

    if valid_rows == 0:
        raise ValueError(f"Nenhuma linha valida encontrada em: {csv_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(output_lines) + "\n", encoding="ascii")

    return {
        "file": csv_path.name,
        "output": output_path.name,
        "total_rows": total_rows,
        "valid_rows": valid_rows,
        "skipped_rows": skipped_rows,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive-dir", default="archive")
    parser.add_argument("--output-dir", default="dados_pre_processados")
    parser.add_argument("--power-col", default="PVPCS_Active_Power")
    parser.add_argument("--voltage-col", default="MG-LV-MSB_AC_Voltage")
    parser.add_argument("--power-unit", choices=["W", "kW", "w", "kw"], default="kW")
    parser.add_argument("--voltage-scale", type=float, default=1.0)
    parser.add_argument("--current-scale", type=float, default=1.0)
    parser.add_argument("--min-voltage", type=float, default=1e-6)
    parser.add_argument("--keep-power-sign", action="store_true")

    args = parser.parse_args()

    archive_dir = Path(args.archive_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    if not archive_dir.exists():
        raise FileNotFoundError(f"Pasta archive nao encontrada: {archive_dir}")

    csv_files = sorted(archive_dir.glob("*.csv"))

    if not csv_files:
        raise FileNotFoundError(f"Nenhum .csv encontrado em: {archive_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)

    reports: list[dict[str, int | str]] = []

    for csv_path in csv_files:
        month_name = csv_path.stem
        output_path = output_dir / f"{month_name}_dataset.txt"

        print(f"Pre-processando {csv_path.name} -> {output_path.name}")

        report = convert_csv(
            csv_path=csv_path,
            output_path=output_path,
            power_col=args.power_col,
            voltage_col=args.voltage_col,
            power_unit=args.power_unit,
            voltage_scale=args.voltage_scale,
            current_scale=args.current_scale,
            min_voltage=args.min_voltage,
            keep_power_sign=args.keep_power_sign,
        )

        reports.append(report)

    report_path = output_dir / "pre_process_report.csv"

    with report_path.open("w", newline="", encoding="utf-8") as f:
        fieldnames = ["file", "output", "total_rows", "valid_rows", "skipped_rows"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(reports)

    print(f"Relatorio salvo em: {report_path}")


if __name__ == "__main__":
    main()
