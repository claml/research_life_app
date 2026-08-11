# Drift schema fixtures

Drift 2.33 recognizes only `drift_schema_vN.json` when generating migration
helpers, while this project's migration brief requires `schema_vN.json` as the
captured fixtures. Keep the required files authoritative and refresh the Drift
aliases before generating helpers:

```powershell
dart run drift_dev schema dump lib/services/database/app_database.dart drift_schemas/schema_v9.json
Copy-Item drift_schemas/schema_v8.json drift_schemas/drift_schema_v8.json -Force
Copy-Item drift_schemas/schema_v9.json drift_schemas/drift_schema_v9.json -Force
New-Item -ItemType Directory -Path test/generated -Force | Out-Null
dart run drift_dev schema generate drift_schemas test/generated/app_database_schema
```

Capture a new baseline fixture before editing the production schema. On Windows
machines where Dart AOT cannot write through a Unicode workspace path, run the
same commands through a temporary ASCII `subst` drive mapping.
