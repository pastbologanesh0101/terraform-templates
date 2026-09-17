app_name: ${app_name}
environment: ${environment}
log_level: ${log_level}
generated_at: "${generated_at}"
feature_flags:
%{ for flag in feature_flags ~}
  - name: ${flag}
    enabled: true
%{ endfor ~}
