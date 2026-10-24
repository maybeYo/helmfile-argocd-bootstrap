{{/*
Build a .dockerconfigjson document from a list of {url, username, password}.
*/}}
{{- define "image-pull-secrets.dockerconfig" -}}
{{- $auths := dict -}}
{{- range $reg := . -}}
{{- $_ := set $auths $reg.url (dict "auth" (printf "%s:%s" $reg.username $reg.password | b64enc)) -}}
{{- end -}}
{{ dict "auths" $auths | toJson }}
{{- end -}}
