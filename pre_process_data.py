from __future__ import annotations

import argparse
import csv
from datetime import datetime
import math
from pathlib import Path


def normalize_name(name: str) -> str:
    return name.replace("\ufeff", "").strip()


def parse_number(value: str) -> float | None:
    if value is None:
        return None

    text = str(value).strip().replace('"', "").replace("'", "")
    if not text:
        return None

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


def clamp_int16(value: int) -> tuple[int, bool]:
    if value < -32768:
        return -32768, True
    if value > 32767:
        return 32767, True
    return value, False


def parse_timestamp(value: str) -> tuple[int, int] | None:
    if value is None:
        return None

    text = str(value).strip().replace('"', "").replace("'", "")
    if not text:
        return None

    formats = (
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y/%m/%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y-%m-%d %H:%M",
    )

    for fmt in formats:
        try:
            timestamp = datetime.strptime(text, fmt)
            return int(timestamp.strftime("%Y%m%d")), int(timestamp.strftime("%H%M%S"))
        except ValueError:
            pass

    return None


def detect_dialect(csv_path: Path) -> csv.Dialect:
    sample = csv_path.read_text(encoding="utf-8-sig", errors="ignore")[:4096]
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        return csv.excel


def convert_csv(
    csv_path: Path,
    output_path: Path,
    timestamp_col: str,
    power_col: str,
    voltage_col: str,
    power_unit: str,
    voltage_scale: float,
    current_scale: float,
    min_voltage: float,
    min_power_watts: float,
    keep_power_sign: bool,
) -> dict[str, int | float | str]:
    dialect = detect_dialect(csv_path)

    total_rows = 0
    valid_rows = 0
    skipped_invalid_rows = 0
    skipped_low_power_rows = 0
    clipped_voltage_rows = 0
    clipped_current_rows = 0

    power_values = []
    voltage_values = []
    current_values = []
    voltage_int_values = []
    current_int_values = []
    output_lines = []

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

        for required in (timestamp_col, power_col, voltage_col):
            if required not in fields:
                raise ValueError(
                    f"Coluna nao encontrada em {csv_path.name}: {required}. "
                    f"Colunas disponiveis: {fields}"
                )

        for row in reader:
            total_rows += 1

            normalized_row = {}
            for original_name, value in row.items():
                if original_name is not None:
                    normalized_row[field_map[original_name]] = value

            timestamp = parse_timestamp(normalized_row.get(timestamp_col))
            power = parse_number(normalized_row.get(power_col))
            voltage = parse_number(normalized_row.get(voltage_col))

            if timestamp is None or power is None or voltage is None or abs(voltage) < min_voltage:
                skipped_invalid_rows += 1
                continue

            if not keep_power_sign:
                power = abs(power)

            if power_unit.lower() == "kw":
                power_watts = power * 1000.0
            elif power_unit.lower() == "w":
                power_watts = power
            else:
                raise ValueError("power_unit deve ser W ou kW.")

            if power_watts < min_power_watts:
                skipped_low_power_rows += 1
                continue

            current = power_watts / voltage

            voltage_int, voltage_clipped = clamp_int16(int(round(voltage * voltage_scale)))
            current_int, current_clipped = clamp_int16(int(round(current * current_scale)))

            clipped_voltage_rows += int(voltage_clipped)
            clipped_current_rows += int(current_clipped)

            timestamp_date, timestamp_time = timestamp
            output_lines.append(f"{timestamp_date} {timestamp_time} {voltage_int} {current_int}")

            valid_rows += 1
            power_values.append(power_watts)
            voltage_values.append(voltage)
            current_values.append(current)
            voltage_int_values.append(voltage_int)
            current_int_values.append(current_int)

    if valid_rows == 0:
        raise ValueError(
            f"Nenhuma linha valida em {csv_path.name}. "
            "Verifique power_col, voltage_col, power_unit e min_power_watts."
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(output_lines) + "\n", encoding="ascii")

    def min0(values):
        return float(min(values)) if values else 0.0

    def max0(values):
        return float(max(values)) if values else 0.0

    def mean0(values):
        return float(sum(values) / len(values)) if values else 0.0

    return {
        "file": csv_path.name,
        "output": output_path.name,
        "total_rows": total_rows,
        "valid_rows": valid_rows,
        "skipped_invalid_rows": skipped_invalid_rows,
        "skipped_low_power_rows": skipped_low_power_rows,
        "clipped_voltage_rows": clipped_voltage_rows,
        "clipped_current_rows": clipped_current_rows,
        "power_watts_min": min0(power_values),
        "power_watts_mean": mean0(power_values),
        "power_watts_max": max0(power_values),
        "voltage_min": min0(voltage_values),
        "voltage_mean": mean0(voltage_values),
        "voltage_max": max0(voltage_values),
        "current_min": min0(current_values),
        "current_mean": mean0(current_values),
        "current_max": max0(current_values),
        "voltage_int_min": min0(voltage_int_values),
        "voltage_int_mean": mean0(voltage_int_values),
        "voltage_int_max": max0(voltage_int_values),
        "current_int_min": min0(current_int_values),
        "current_int_mean": mean0(current_int_values),
        "current_int_max": max0(current_int_values),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive-dir", default="archive")
    parser.add_argument("--output-dir", default="dados_pre_processados")
    parser.add_argument("--timestamp-col", default="Timestamp")
    parser.add_argument("--power-col", default="PVPCS_Active_Power")
    parser.add_argument("--voltage-col", default="MG-LV-MSB_AC_Voltage")
    parser.add_argument("--power-unit", choices=["W", "kW", "w", "kw"], default="kW")
    parser.add_argument("--voltage-scale", type=float, default=16.0)
    parser.add_argument("--current-scale", type=float, default=128.0)
    parser.add_argument("--min-voltage", type=float, default=1e-6)
    parser.add_argument("--min-power-watts", type=float, default=10.0)
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
    reports = []

    for csv_path in csv_files:
        output_path = output_dir / f"{csv_path.stem}_dataset.txt"
        print(f"Pre-processando {csv_path.name} -> {output_path.name}")

        reports.append(convert_csv(
            csv_path=csv_path,
            output_path=output_path,
            timestamp_col=args.timestamp_col,
            power_col=args.power_col,
            voltage_col=args.voltage_col,
            power_unit=args.power_unit,
            voltage_scale=args.voltage_scale,
            current_scale=args.current_scale,
            min_voltage=args.min_voltage,
            min_power_watts=args.min_power_watts,
            keep_power_sign=args.keep_power_sign,
        ))

    report_path = output_dir / "pre_process_report.csv"

    with report_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(reports[0].keys()))
        writer.writeheader()
        writer.writerows(reports)

    print(f"Relatorio salvo em: {report_path}")


if __name__ == "__main__":
    main()
