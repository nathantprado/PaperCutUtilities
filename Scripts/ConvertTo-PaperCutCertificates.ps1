<#
    .SYNOPSIS
    Converts a certificate from a Windows certificate store into files for PaperCut servers.

    .DESCRIPTION
    Reads the certificate identified by its thumbprint from a Windows certificate store
    and exports an encrypted PFX for the PaperCut MF application server, a Base64-encoded
    CER public certificate, and a PEM-encoded PKCS#8 private key for Mobility Print and
    Print Deploy.

    The certificate must have an RSA private key that is configured for export. The
    output directory must already exist. The private key files (PFX and PEM) should be
    stored securely and not placed in a publicly accessible directory.

    .PARAMETER Thumbprint
    Thumbprint of the certificate to convert. The certificate must be present in the
    selected certificate store and have an exportable RSA private key.

    .PARAMETER OutputDirectory
    Directory in which to write the output files. Defaults to the current working
    directory. The directory must already exist.

    .PARAMETER PfxPassword
    Secure password used to protect the exported PFX. If omitted, the script prompts
    for a password.

    .PARAMETER CertStore
    Windows certificate store path to search. Defaults to Cert:\LocalMachine\My.

    .PARAMETER PfxFileName
    Base name for the exported PFX file, without the .pfx extension. Defaults to
    PaperCutCertificate.

    .OUTPUTS
    System.Collections.Hashtable
    Returns a hashtable with PFX, CER, and PEM entries containing the output files.

    .EXAMPLE
    .\ConvertTo-PaperCutCertificates.ps1 -Thumbprint '0123456789ABCDEF0123456789ABCDEF01234567' `
        -OutputDirectory 'C:\PaperCut\Certificates'

    Exports the certificate files to the specified directory and prompts for the PFX
    password.

    .EXAMPLE
    $password = Read-Host 'PFX password' -AsSecureString
    .\ConvertCertificateFiles.ps1 -Thumbprint '0123456789ABCDEF0123456789ABCDEF01234567' `
        -OutputDirectory 'C:\PaperCut\Certificates' -PfxPassword $password `
        -CertStore 'Cert:\CurrentUser\My' -PfxFileName 'PaperCutServer'

    Exports files using the specified store and PFX filename.
#>
param(
    [Parameter(Mandatory)]
    [String]$Thumbprint,
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]$OutputDirectory = $PWD.Path,
    [SecureString]$PfxPassword = (Read-Host -Prompt "Enter encryption password to export PFX certificate" -AsSecureString),

    [Parameter(DontShow)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]$CertStore = 'Cert:\LocalMachine\My',
    [Parameter(DontShow)]
    [String]$PfxFileName = 'PaperCutCertificate'
)

begin {
    $Thumbprint = $Thumbprint.Trim()
    $Cert = Get-Item "$CertStore\$Thumbprint" -ErrorAction Stop
}
process {

}
end {
    #region Convert PKCS12 private key to PEM format
    $RSA = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
    if ($null -eq $RSA -or $RSA.Key.ExportPolicy -eq 'None') {
        throw "Certificate is not configured to allow the private key to be exported."
    }
    $KeyBytes = $RSA.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
    $FlatBase64 = [Convert]::ToBase64String($KeyBytes)
    $64CharLines = [System.Text.RegularExpressions.Regex]::Matches($FlatBase64, '.{1,64}') | ForEach-Object { $_.Value }
    $PEMBody = $64CharLines -join "`n"
    $PEMOutput = "-----BEGIN PRIVATE KEY-----`n$pemBody`n-----END PRIVATE KEY-----`n"
    
    [System.IO.File]::WriteAllText("$OutputDirectory\tls.pem", $PEMOutput, [System.Text.Encoding]::ASCII)
    #endregion

    #region Export public certificate as Base64 encoded CER
    Export-Certificate -Type CERT -Force -FilePath "$OutputDirectory\tls.der" -Cert $Cert | Out-Null
    certutil -encode -f "$OutputDirectory\tls.der" "$OutputDirectory\tls.cer" | Out-Null
    Remove-Item -Path "$OutputDirectory\tls.der"
    #endregion

    # Export PFX
    Export-PfxCertificate -CryptoAlgorithmOption AES256_SHA256 -Password $PfxPassword -FilePath "$OutputDirectory\$PfxFileName.pfx" -Cert $Cert | Out-Null

    $Result = @{
        PFX = (Get-Item -Path "$OutputDirectory\$PfxFileName.pfx")
        CER = (Get-Item -Path "$OutputDirectory\tls.cer")
        PEM = (Get-Item -Path "$OutputDirectory\tls.pem")
    }

    Write-Warning "Do not leave the PFX certificate in a publically accessible directory."
    return $Result
}
