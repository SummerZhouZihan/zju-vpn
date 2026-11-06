function Get-UiText {
    param([string]$Key, [ValidateSet('zh-CN','en')][string]$Language = 'zh-CN', [object[]]$Values = @())
    if (-not $script:UiLocales) { $script:UiLocales = @{} }
    if (-not $script:UiLocales.ContainsKey($Language)) {
        $path = Join-Path $script:CampusRoot ("resources\locales\{0}.json" -f $Language)
        $script:UiLocales[$Language] = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $property = $script:UiLocales[$Language].PSObject.Properties[$Key]
    if (-not $property) { throw "Missing interface translation: $Key" }
    $text = [string]$property.Value
    if ($Values.Count -gt 0) { return [string]::Format([Globalization.CultureInfo]::InvariantCulture, $text, $Values) }
    return $text
}
