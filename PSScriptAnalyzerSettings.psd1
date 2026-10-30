@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingUsernameAndPasswordParams'
        'PSUseSingularNouns'
        'PSReviewUnusedParameter'
        'PSAvoidUsingComputerNameHardcoded'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
