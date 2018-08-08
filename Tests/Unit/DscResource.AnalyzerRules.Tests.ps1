$script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName
$script:ModuleName = (Get-Item -Path $PSCommandPath).BaseName -replace '\.Tests'
$script:ModuleRootPath = Join-Path -Path $script:ProjectRoot -ChildPath $script:ModuleName

Import-Module -Name (Join-Path -Path $script:ProjectRoot -ChildPath 'TestHelper.psm1') -Force
<#
    Script analyzer is needed to be able to load the the DscResource.AnalyzerRules
    module, and be able to call Invoke-PSScriptAnalyzer.
#>
Import-PSScriptAnalyzer
Import-Module -Name $script:ModuleRootPath

$modulePath = Join-Path -Path $script:ModuleRootPath -ChildPath "$($script:ModuleName).psm1"
Import-LocalizedData -BindingVariable localizedData -BaseDirectory $script:ModuleRootPath -FileName "$($script:ModuleName).psd1"

<#
    .SYNOPSIS
        Helper function to return Ast objects,
        to be able to test custom rules.

    .PARAMETER ScriptDefinition
        The script definition to return ast for.

    .PARAMETER AstType
        The Ast type to return;
        System.Management.Automation.Language.ParameterAst,
        System.Management.Automation.Language.NamedAttributeArgumentAst,
        etc.
#>
function Get-AstFromDefinition
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Language.Ast[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptDefinition,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AstType
    )

    $parseErrors = $null
    $definitionAst = [System.Management.Automation.Language.Parser]::ParseInput($ScriptDefinition, [ref] $null, [ref] $parseErrors)

    if ($parseErrors)
    {
        throw $parseErrors
    }

    $astFilter = {
        $args[0] -is $AstType
    }

    return $definitionAst.FindAll($astFilter, $true)
}

Describe 'Measure-ParameterBlockParameterAttribute' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.ParameterAst'
        }

        Context 'When ParameterAttribute is missing' {
            It 'Should write the correct record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ParameterBlockParameterAttribute -ParameterAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
            }
        }

        Context 'When ParameterAttribute is not declared first' {
            It 'Should write the correct record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            [ValidateSet("one", "two")]
                            [Parameter()]
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ParameterBlockParameterAttribute -ParameterAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeWrongPlace
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeWrongPlace"
            }
        }

        Context 'When ParameterAttribute is in lower-case' {
            It 'Should write the correct record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            [parameter()]
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ParameterBlockParameterAttribute -ParameterAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeLowerCase
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeLowerCase"
            }
        }

        Context 'When ParameterAttribute is written correctly' {
            It 'Should not write a record' {
                $definition = '
                    function Get-TargetResource
                    {
                        param (
                            [Parameter()]
                            $ParameterName1,

                            [Parameter(Mandatory = $true)]
                            $ParameterName2
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                Measure-ParameterBlockParameterAttribute -ParameterAst $mockAst[0] | Should -BeNullOrEmpty
                Measure-ParameterBlockParameterAttribute -ParameterAst $mockAst[1] | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When ParameterAttribute is missing' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
            }
        }

        Context 'When ParameterAttribute is present' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter()]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When ParameterAttribute is not declared first' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [ValidateSet("one", "two")]
                            [Parameter()]
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeWrongPlace
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeWrongPlace"
            }
        }

        Context 'When ParameterAttribute is declared first' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter()]
                            [ValidateSet("one", "two")]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When ParameterAttribute is in lower-case' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [parameter()]
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeLowerCase
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeLowerCase"
            }
        }

        Context 'When ParameterAttribute is written in the correct casing' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter()]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When ParameterAttribute is missing from two parameters' {
            It 'Should write the correct records' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            $ParameterName1,

                            $ParameterName2
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 2
                $record[0].Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record[1].Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record[0].RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
                $record[1].RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
            }
        }

        Context 'When ParameterAttribute is missing and in lower-case' {
            It 'Should write the correct records' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            $ParameterName1,

                            [parameter()]
                            $ParameterName2
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 2
                $record[0].Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record[1].Message | Should -Be $localizedData.ParameterBlockParameterAttributeLowerCase
                $record[0].RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
                $record[1].RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeLowerCase"
            }
        }

        Context 'When ParameterAttribute is missing from a second parameter' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter()]
                            $ParameterName1,

                            $ParameterName2
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
            }
        }

        Context 'When Parameter is part of a method in a class' {
            It 'Should not return any records' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    class Resource
                    {
                        [void] Get_TargetResource($ParameterName1,$ParameterName2)
                        {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }

        Context 'When Parameter is part of a script block that is part of a property in a class' {
            It 'Should return records for the Parameter in the script block' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    class Resource
                    {
                        [void] Get_TargetResource($ParameterName1,$ParameterName2)
                        {
                        }

                        [Func[Int,Int]] $MakeInt = {
                            [Parameter(Mandatory=$true)]
                            Param
                            (
                                [int] $Input
                            )
                            $Input * 2
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterAttributeMissing
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterAttributeMissing"
            }
        }
    }
}

Describe 'Measure-ParameterBlockMandatoryNamedArgument' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.NamedAttributeArgumentAst'
        }

        Context 'When Mandatory is included and set to $false' {
            It 'Should write the correct record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $false)]
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType

                $record = Measure-ParameterBlockMandatoryNamedArgument -NamedAttributeArgumentAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory is lower-case' {
            It 'Should write the correct record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(mandatory = $true)]
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType

                $record = Measure-ParameterBlockMandatoryNamedArgument -NamedAttributeArgumentAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory does not include an explicit argument' {
            It 'Should write the correct record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory)]
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType

                $record = Measure-ParameterBlockMandatoryNamedArgument -NamedAttributeArgumentAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory is correctly written' {
            It 'Should not write a record' {
                $definition = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $true)]
                            $ParameterName
                        )
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                Measure-ParameterBlockMandatoryNamedArgument -NamedAttributeArgumentAst $mockAst[0] | Should -BeNullOrEmpty
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When Mandatory is included and set to $false' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $false)]
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory is lower-case' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(mandatory = $true)]
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory does not include an explicit argument' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory)]
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory is incorrectly written and other parameters are used' {
            It 'Should write the correct record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $false, ParameterSetName = "SetName")]
                            $ParameterName
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory is correctly written' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $true)]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When Mandatory is not present and other parameters are' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(HelpMessage = "HelpMessage")]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When Mandatory is correctly written and other parameters are listed' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $true, ParameterSetName = "SetName")]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When Mandatory is correctly written and not placed first' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(ParameterSetName = "SetName", Mandatory = $true)]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When Mandatory is correctly written and other attributes are listed' {
            It 'Should not write a record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $true)]
                            [ValidateSet("one", "two")]
                            $ParameterName
                        )
                    }
                '

                Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters | Should -BeNullOrEmpty
            }
        }

        Context 'When Mandatory Attribute NamedParameter is in a class' {
            It 'Should not return any records' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    [DscResource()]
                    class Resource
                    {
                        [DscProperty(Key)]
                        [string] $DscKeyString

                        [DscProperty(Mandatory)]
                        [int] $DscNum

                        [Resource] Get()
                        {
                            return $this
                        }

                        [void] Set()
                        {
                        }

                        [bool] Test()
                        {
                            return $true
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }

        Context 'When Mandatory Attribute NamedParameter is in script block in a property in a class' {
            It 'Should return records for NameParameter in the ScriptBlock only' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    [DscResource()]
                    class Resource
                    {
                        [DscProperty(Key)]
                        [string] $DscKeyString

                        [DscProperty(Mandatory)]
                        [int] $DscNum

                        [Resource] Get()
                        {
                            return $this
                        }

                        [void] Set()
                        {
                        }

                        [bool] Test()
                        {
                            return $true
                        }

                        [Func[Int,Int]] $MakeInt = {
                            [Parameter(Mandatory=$true)]
                            Param
                            (
                                [Parameter(Mandatory)]
                                [int] $Input
                            )
                            $Input * 2
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When Mandatory is incorrectly set on two parameters' {
            It 'Should write the correct records' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory)]
                            $ParameterName1,

                            [Parameter(Mandatory = $false)]
                            $ParameterName2
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 2
                $record[0].Message | Should -Be $localizedData.ParameterBlockParameterMandatoryAttributeWrongFormat
                $record[1].Message | Should -Be $localizedData.ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat
                $record[0].RuleName | Should -Be "$($script:moduleName)\ParameterBlockParameterMandatoryAttributeWrongFormat"
                $record[1].RuleName | Should -Be "$($script:moduleName)\ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat"
            }
        }

        Context 'When ParameterAttribute is set to $false and in lower-case' {
            It 'Should write the correct records' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-TargetResource
                    {
                        Param (
                            [Parameter(Mandatory = $true)]
                            $ParameterName1,

                            [Parameter(mandatory = $false)]
                            $ParameterName2
                        )
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat
                $record.RuleName | Should -Be "$($script:moduleName)\ParameterBlockNonMandatoryParameterMandatoryAttributeWrongFormat"
            }
        }
    }
}

Describe 'Measure-FunctionBlockBraces' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.FunctionDefinitionAst'
        }

        Context 'When a functions opening brace is on the same line as the function keyword' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something {
                        [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-FunctionBlockBraces -FunctionDefinitionAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.FunctionOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceNotOnSameLine"
            }
        }

        Context 'When function opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {   [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-FunctionBlockBraces -FunctionDefinitionAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.FunctionOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When function opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {

                        [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-FunctionBlockBraces -FunctionDefinitionAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.FunctionOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When a functions opening brace is on the same line as the function keyword' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something {
                        [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.FunctionOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceNotOnSameLine"
            }
        }

        Context 'When two functions has opening brace is on the same line as the function keyword' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something {
                    }

                    function Get-SomethingElse {
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 2
                $record[0].Message | Should -Be $localizedData.FunctionOpeningBraceNotOnSameLine
                $record[1].Message | Should -Be $localizedData.FunctionOpeningBraceNotOnSameLine
                $record[0].RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceNotOnSameLine"
                $record[1].RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceNotOnSameLine"
            }
        }

        Context 'When function opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {   [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.FunctionOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When function opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {

                        [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.FunctionOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\FunctionOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When function follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        [CmdletBinding()]
                        [OutputType([System.Boolean])]
                        param
                        (
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $Variable1
                        )

                        return $true
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-IfStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.IfStatementAst'
        }

        Context 'When if-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        if ($true) {
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-IfStatement -IfStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.IfStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When if-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        if ($true)
                        { return $true
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-IfStatement -IfStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.IfStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When if-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        if ($true)
                        {

                            return $true
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-IfStatement -IfStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.IfStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When if-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        if ($true) {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.IfStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When two if-statements has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        if ($true) {
                        }

                        if ($true) {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 2
                $record[0].Message | Should -Be $localizedData.IfStatementOpeningBraceNotOnSameLine
                $record[1].Message | Should -Be $localizedData.IfStatementOpeningBraceNotOnSameLine
                $record[0].RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceNotOnSameLine"
                $record[1].RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When if-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        if ($true)
                        { return $true
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.IfStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When if-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        if ($true)
                        {

                            return $true
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.IfStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\IfStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When if-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        if ($true)
                        {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }

        # Regression test for issue reported in review comment for PR #180.
        Context 'When if-statement is using braces in the evaluation expression' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        if (Get-Command | Where-Object -FilterScript { $_.Name -eq ''Get-Help'' } )
                        {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-ForEachStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.ForEachStatementAst'
        }

        Context 'When foreach-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray) {
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ForEachStatement -ForEachStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ForEachStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForEachStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When foreach-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray)
                        {   $stringText
                        }
                    }
                '
                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ForEachStatement -ForEachStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ForEachStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForEachStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When foreach-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray)
                        {

                            $stringText
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ForEachStatement -ForEachStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ForEachStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForEachStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When foreach-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray) {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.ForEachStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForEachStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When foreach-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray)
                        {   $stringText
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.ForEachStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForEachStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When foreach-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray)
                        {

                            $stringText
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.ForEachStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForEachStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When foreach-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $myArray = @()
                        foreach ($stringText in $myArray)
                        {
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-DoUntilStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.DoUntilStatementAst'
        }

        Context 'When DoUntil-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 0

                        do {
                            $i++
                        } until ($i -eq 2)
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-DoUntilStatement -DoUntilStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.DoUntilStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoUntilStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When DoUntil-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 0

                        do
                        { $i++
                        } until ($i -eq 2)
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-DoUntilStatement -DoUntilStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.DoUntilStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoUntilStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When DoUntil-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 0

                        do
                        {

                            $i++
                        } until ($i -eq 2)
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-DoUntilStatement -DoUntilStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.DoUntilStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoUntilStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When DoUntil-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 0

                        do {
                            $i++
                        } until ($i -eq 2)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.DoUntilStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoUntilStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When DoUntil-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 0

                        do
                        { $i++
                        } until ($i -eq 2)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.DoUntilStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoUntilStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When DoUntil-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 0

                        do
                        {

                            $i++
                        } until ($i -eq 2)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.DoUntilStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoUntilStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When DoUntil-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 0

                        do
                        {
                            $i++
                        } until ($i -eq 2)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-DoWhileStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.DoWhileStatementAst'
        }

        Context 'When DoWhile-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 10

                        do {
                            $i--
                        } while ($i -gt 0)
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-DoWhileStatement -DoWhileStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.DoWhileStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoWhileStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When DoWhile-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 10

                        do
                        { $i--
                        } while ($i -gt 0)
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-DoWhileStatement -DoWhileStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.DoWhileStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoWhileStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When DoWhile-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 10

                        do
                        {

                            $i--
                        } while ($i -gt 0)
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-DoWhileStatement -DoWhileStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.DoWhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoWhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When DoWhile-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        do {
                            $i--
                        } while ($i -gt 0)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.DoWhileStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoWhileStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When DoWhile-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        do
                        { $i--
                        } while ($i -gt 0)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.DoWhileStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoWhileStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When DoWhile-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        do
                        {

                            $i--
                        } while ($i -gt 0)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.DoWhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\DoWhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When DoWhile-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        do
                        {
                            $i--
                        } while ($i -gt 0)
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-WhileStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.WhileStatementAst'
        }

        Context 'When While-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0) {
                            $i--
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-WhileStatement -WhileStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.WhileStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\WhileStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When While-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0)
                        { $i--
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-WhileStatement -WhileStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.WhileStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\WhileStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When While-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0)
                        {

                            $i--
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-WhileStatement -WhileStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.WhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\WhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When While-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0) {
                            $i--
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.WhileStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\WhileStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When While-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0)
                        { $i--
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.WhileStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\WhileStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When While-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0)
                        {

                            $i--
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.WhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\WhileStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When While-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $i = 10

                        while ($i -gt 0)
                        {
                            $i--
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-SwitchStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.SwitchStatementAst'
        }

        Context 'When Switch-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value) {
                            1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-SwitchStatement -SwitchStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When Switch-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value)
                        {   1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-SwitchStatement -SwitchStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When Switch-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value)
                        {

                            1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-SwitchStatement -SwitchStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When Switch-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value) {
                            1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceNotOnSameLine"
            }
        }

        # Regression test.
        Context 'When Switch-statement has an opening brace on the same line, and also has a clause with an opening brace on the same line' {
            It 'Should write only one error record, and the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value) {
                            1 { ''one'' }
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When Switch-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value)
                        {   1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When Switch-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value)
                        {

                            1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.SwitchStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\SwitchStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When Switch-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        $value = 1

                        switch ($value)
                        {
                            1
                            {
                                ''one''
                            }
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-ForStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.ForStatementAst'
        }

        Context 'When For-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++) {
                            $value = 1
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ForStatement -ForStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ForStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When For-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++)
                        { $value = 1
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ForStatement -ForStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ForStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When For-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++)
                        {

                            $value = 1
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-ForStatement -ForStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.ForStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When For-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++) {
                            $value = 1
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.ForStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When For-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++)
                        { $value = 1
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.ForStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When For-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++)
                        {

                            $value = 1
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.ForStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\ForStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When For-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        for ($a = 1; $a -lt 2; $a++)
                        {
                            $value = 1
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-TryStatement' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.TryStatementAst'
        }

        Context 'When Try-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        try {
                            $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-TryStatement -TryStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.TryStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\TryStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When Try-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        try
                        { $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-TryStatement -TryStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.TryStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\TryStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When Try-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        try
                        {

                            $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-TryStatement -TryStatementAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.TryStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\TryStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When Try-statement has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try {
                            $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.TryStatementOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\TryStatementOpeningBraceNotOnSameLine"
            }
        }

        Context 'When Try-statement opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        { $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.TryStatementOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\TryStatementOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When Try-statement opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        {

                            $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.TryStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\TryStatementOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When Try-statement follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-CatchClause' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.CatchClauseAst'
        }

        Context 'When Catch-clause has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch {
                            throw
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-CatchClause -CatchClauseAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.CatchClauseOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\CatchClauseOpeningBraceNotOnSameLine"
            }
        }

        Context 'When Catch-clause opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch
                        { throw
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-CatchClause -CatchClauseAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.CatchClauseOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\CatchClauseOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When Catch-clause opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $definition = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch
                        {

                            throw
                        }
                    }
                '

                $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                $record = Measure-CatchClause -CatchClauseAst $mockAst[0]
                ($record | Measure-Object).Count | Should -Be 1
                $record.Message | Should -Be $localizedData.CatchClauseOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\CatchClauseOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'When Catch-clause has an opening brace on the same line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch {
                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.CatchClauseOpeningBraceNotOnSameLine
                $record.RuleName | Should -Be "$($script:moduleName)\CatchClauseOpeningBraceNotOnSameLine"
            }
        }

        Context 'When Catch-clause opening brace is not followed by a new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch
                        { throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.CatchClauseOpeningBraceShouldBeFollowedByNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\CatchClauseOpeningBraceShouldBeFollowedByNewLine"
            }
        }

        Context 'When Catch-clause opening brace is followed by more than one new line' {
            It 'Should write the correct error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch
                        {

                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                ($record | Measure-Object).Count | Should -BeExactly 1
                $record.Message | Should -Be $localizedData.CatchClauseOpeningBraceShouldBeFollowedByOnlyOneNewLine
                $record.RuleName | Should -Be "$($script:moduleName)\CatchClauseOpeningBraceShouldBeFollowedByOnlyOneNewLine"
            }
        }

        Context 'When Catch-clause follows style guideline' {
            It 'Should not write an error record' {
                $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    function Get-Something
                    {
                        try
                        {
                            $value = 1
                        }
                        catch
                        {
                            throw
                        }
                    }
                '

                $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                $record | Should -BeNullOrEmpty
            }
        }
    }
}

Describe 'Measure-TypeDefinition' {
    Context 'When calling the function directly' {
        BeforeAll {
            $astType = 'System.Management.Automation.Language.TypeDefinitionAst'
        }

        Context 'Enum' {
            Context 'When Enum has an opening brace on the same line' {
                It 'Should write the correct error record' {
                    $definition = '
                        enum Test {
                            Good
                            Bad
                        }
                    '

                    $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                    $record = Measure-TypeDefinition -TypeDefinitionAst $mockAst[0]
                    ($record | Measure-Object).Count | Should -Be 1
                    $record.Message | Should -Be $localizedData.EnumOpeningBraceNotOnSameLine
                    $record.RuleName | Should -Be "$($script:moduleName)\EnumOpeningBraceNotOnSameLine"
                }
            }

            Context 'When Enum Opening brace is not followed by a new line' {
                It 'Should write the correct error record' {
                    $definition = '
                        enum Test
                        { Good
                            Bad
                        }
                    '
                    $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                    $record = Measure-TypeDefinition -TypeDefinitionAst $mockAst[0]
                    ($record | Measure-Object).Count | Should -Be 1
                    $record.Message | Should -Be $localizedData.EnumOpeningBraceShouldBeFollowedByNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\EnumOpeningBraceShouldBeFollowedByNewLine"
                }
            }

            Context 'When Enum opening brace is followed by more than one new line' {
                It 'Should write the correct error record' {
                    $definition = '
                        enum Test
                        {

                            Good
                            Bad
                        }
                    '

                    $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                    $record = Measure-TypeDefinition -TypeDefinitionAst $mockAst[0]
                    ($record | Measure-Object).Count | Should -Be 1
                    $record.Message | Should -Be $localizedData.EnumOpeningBraceShouldBeFollowedByOnlyOneNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\EnumOpeningBraceShouldBeFollowedByOnlyOneNewLine"
                }
            }
        }

        Context 'Class' {
            Context 'When Class has an opening brace on the same line' {
                It 'Should write the correct error record' {
                    $definition = '
                        class Test {
                            [int] $Good
                            [Void] Bad()
                            {
                            }
                        }
                    '

                    $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                    $record = Measure-TypeDefinition -TypeDefinitionAst $mockAst[0]
                    ($record | Measure-Object).Count | Should -Be 1
                    $record.Message | Should -Be $localizedData.ClassOpeningBraceNotOnSameLine
                    $record.RuleName | Should -Be "$($script:moduleName)\ClassOpeningBraceNotOnSameLine"
                }
            }

            Context 'When Class Opening brace is not followed by a new line' {
                It 'Should write the correct error record' {
                    $definition = '
                        class Test
                        {   [int] $Good
                            [Void] Bad()
                            {
                            }
                        }
                    '

                    $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                    $record = Measure-TypeDefinition -TypeDefinitionAst $mockAst[0]
                    ($record | Measure-Object).Count | Should -Be 1
                    $record.Message | Should -Be $localizedData.ClassOpeningBraceShouldBeFollowedByNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\ClassOpeningBraceShouldBeFollowedByNewLine"
                }
            }

            Context 'When Class opening brace is followed by more than one new line' {
                It 'Should write the correct error record' {
                    $definition = '
                        class Test
                        {

                            [int] $Good
                            [Void] Bad()
                            {
                            }
                        }
                    '

                    $mockAst = Get-AstFromDefinition -ScriptDefinition $definition -AstType $astType
                    $record = Measure-TypeDefinition -TypeDefinitionAst $mockAst[0]
                    ($record | Measure-Object).Count | Should -Be 1
                    $record.Message | Should -Be $localizedData.ClassOpeningBraceShouldBeFollowedByOnlyOneNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\ClassOpeningBraceShouldBeFollowedByOnlyOneNewLine"
                }
            }
        }
    }

    Context 'When calling PSScriptAnalyzer' {
        BeforeAll {
            $invokeScriptAnalyzerParameters = @{
                CustomRulePath = $modulePath
            }
        }

        Context 'Enum' {
            Context 'When Enum has an opening brace on the same line' {
                It 'Should write the correct error record' {
                    $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    enum Test {
                        Good
                        Bad
                    }
                '

                    $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                    ($record | Measure-Object).Count | Should -BeExactly 1
                    $record.Message | Should -Be $localizedData.EnumOpeningBraceNotOnSameLine
                    $record.RuleName | Should -Be "$($script:moduleName)\EnumOpeningBraceNotOnSameLine"
                }
            }

            Context 'When Enum Opening brace is not followed by a new line' {
                It 'Should write the correct error record' {
                    $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    enum Test
                    { Good
                        Bad
                    }
                '
                    $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                    ($record | Measure-Object).Count | Should -BeExactly 1
                    $record.Message | Should -Be $localizedData.EnumOpeningBraceShouldBeFollowedByNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\EnumOpeningBraceShouldBeFollowedByNewLine"
                }
            }

            Context 'When Enum opening brace is followed by more than one new line' {
                It 'Should write the correct error record' {
                    $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    enum Test
                    {

                        Good
                        Bad
                    }
                '

                    $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                    ($record | Measure-Object).Count | Should -BeExactly 1
                    $record.Message | Should -Be $localizedData.EnumOpeningBraceShouldBeFollowedByOnlyOneNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\EnumOpeningBraceShouldBeFollowedByOnlyOneNewLine"
                }
            }
        }

        Context 'Class' {
            Context 'When Class has an opening brace on the same line' {
                It 'Should write the correct error record' {
                    $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    class Test {
                        [int] $Good
                        [Void] Bad()
                        {
                        }
                    }
                '

                    $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                    ($record | Measure-Object).Count | Should -BeExactly 1
                    $record.Message | Should -Be $localizedData.ClassOpeningBraceNotOnSameLine
                    $record.RuleName | Should -Be "$($script:moduleName)\ClassOpeningBraceNotOnSameLine"
                }
            }

            Context 'When Class Opening brace is not followed by a new line' {
                It 'Should write the correct error record' {
                    $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    class Test
                    {   [int] $Good
                        [Void] Bad()
                        {
                        }
                    }
                '

                    $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                    ($record | Measure-Object).Count | Should -BeExactly 1
                    $record.Message | Should -Be $localizedData.ClassOpeningBraceShouldBeFollowedByNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\ClassOpeningBraceShouldBeFollowedByNewLine"
                }
            }

            Context 'When Class opening brace is followed by more than one new line' {
                It 'Should write the correct error record' {
                    $invokeScriptAnalyzerParameters['ScriptDefinition'] = '
                    class Test
                    {

                        [int] $Good
                        [Void] Bad()
                        {
                        }
                    }
                '

                    $record = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters
                    ($record | Measure-Object).Count | Should -BeExactly 1
                    $record.Message | Should -Be $localizedData.ClassOpeningBraceShouldBeFollowedByOnlyOneNewLine
                    $record.RuleName | Should -Be "$($script:moduleName)\ClassOpeningBraceShouldBeFollowedByOnlyOneNewLine"
                }
            }
        }
    }
}
