Param(
    [Parameter(Mandatory)]
    [String]$Thumbprint,
    [String]$OutputDirectory = $PWD.Path,
    [Parameter(Mandatory)]
    [SecureString]$PfxPassword,

    [Parameter(DontShow)]
    [string]$CertStore = 'Cert:\LocalMachine\My'
)

$Cert = Get-Item "$CertStore\$Thumbprint"

#region Convert PKCS12 private key to PEM format
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
If($rsa.Key.ExportPolicy -eq 'None' -or $null -eq $rsa){
    Throw "Certificate is not configured to allow the private key to be exported."
}
$KeyBytes = $rsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
$FlatBase64 = [Convert]::ToBase64String($KeyBytes)
$64CharLines = [System.Text.RegularExpressions.Regex]::Matches($FlatBase64, '.{1,64}') | ForEach-Object { $_.Value }
$PEMBody = $64CharLines -join "`n"
$PEMOutput = "-----BEGIN PRIVATE KEY-----`n$pemBody`n-----END PRIVATE KEY-----`n"

[System.IO.File]::WriteAllText("$OutputDirectory\tls.pem",$PEMOutput, [System.Text.Encoding]::ASCII)
#endregion

#region Export public certificate as Base64 encoded CER
Export-Certificate -Type CERT -Force -FilePath "$OutputDirectory\tls.der" -Cert $Cert | Out-Null
certutil -encode -f "$OutputDirectory\tls.der" "$OutputDirectory\tls.cer" | Out-Null
Remove-Item -Path "$OutputDirectory\tls.der"
#endregion

# Export PKCS12
Export-PfxCertificate -CryptoAlgorithmOption AES256_SHA256 -Password $PfxPassword -FilePath "$OutputDirectory\PaperCutCertificate.pfx"-Cert $Cert | Out-Null

$Result = @{
    PKCS12 = (Get-Item -Path "$OutputDirectory\PaperCutCertificate.pfx")
    CER = (Get-Item -Path "$OutputDirectory\tls.cer")
    PEM = (Get-Item -Path "$OutputDirectory\tls.pem")
}

Write-Warning "Do not leave the PKCS12 certificate in a publically accessible directory."
return $Result
