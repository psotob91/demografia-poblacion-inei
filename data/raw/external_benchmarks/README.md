# External Benchmarks

This folder stores local benchmark inputs that let `demografia-poblacion-inei` run its base pipeline without a runtime dependency on sibling repositories.

Current active file:

- `peru_life_table_all_years_closed_80_109.csv`

Semantics:

- derived from `tabla-mortalidad-peru`;
- restricted to closed ages `80:109`;
- excludes the open `110+` interval by design;
- used only to anchor the high-age population tail before internal Kannisto extension to `125`.

Refresh process:

```powershell
Rscript .\scripts\refresh_external_benchmarks.R
```
