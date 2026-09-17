{
  "app_name": "${app_name}",
  "environment": "${environment}",
  "log_level": "${log_level}",
  "generated_at": "${generated_at}",
  "feature_flags": [
%{ for idx, flag in feature_flags ~}
    {
      "name": "${flag}",
      "enabled": true
    }%{ if idx < length(feature_flags) - 1 },%{ endif }
%{ endfor ~}
  ]
}
