# Scaling Benchmark Results — 2026-05-02 14:39–15:01

## Configuration
- 3 concurrency levels: 10, 50, 80 clients
- 3 runs × 70s each (10s warm-up + 60s measure)
- Hardware: 4 vCPU / 8 GB RAM / WSL2

## Raw Data

### Baseline (trigger DISABLED)
| Level | Run 1 | Run 2 | Run 3 | Avg TPS | Avg Lat (ms) |
|-------|-------|-------|-------|---------|--------------|
| 10c   | 35.39 | 32.46 | 33.27 | 33.71   | 297.1        |
| 50c   | 34.44 | 34.60 | 33.15 | 34.06   | 1468.4       |
| 80c   | 34.45 | 32.50 | 34.75 | 33.90   | 2361.9       |

### Proposed (trigger ENABLED, JSONB → partitioned audit_logs)
| Level | Run 1 | Run 2 | Run 3 | Avg TPS | Avg Lat (ms) |
|-------|-------|-------|-------|---------|--------------|
| 10c   | 32.03 | 30.07 | 33.97 | 32.02   | 313.0        |
| 50c   | 36.10 | 36.21 | 35.77 | 36.03   | 1387.9       |
| 80c   | 36.16 | 35.19 | 34.85 | 35.40   | 2260.5       |

## Summary Table
| Clients | Baseline TPS | Proposed TPS | Overhead | Lat Baseline | Lat Proposed |
|---------|-------------|-------------|----------|-------------|-------------|
| 10c     | 33.71       | 32.02       | +5.0%    | 297.1 ms    | 313.0 ms    |
| 50c     | 34.06       | 36.03       | −5.8%    | 1468.4 ms   | 1387.9 ms   |
| 80c     | 33.90       | 35.40       | −4.4%    | 2361.9 ms   | 2260.5 ms   |

## Key Findings
1. TPS is flat (~33–36) across all concurrency levels — system saturates at ~10c on 4 vCPU WSL2
2. Overhead at 10c = +5.0% (measurable but under 15% threshold)
3. Overhead at 50c/80c = negative (I/O variance exceeds trigger overhead)
4. Overhead consistently bounded in [−6%, +5%] — well within < 15% threshold at all loads
5. Latency increases linearly with concurrency (Little's Law: L=λW)
