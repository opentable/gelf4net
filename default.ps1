properties {
	$TargetFramework = "net-4.0"
	$DownloadDependentPackages = $true
	$UploadPackage = $false
	$NugetKey = ""
}

$baseDir  = resolve-path .
$releaseRoot = "$baseDir\Release"
$releaseDir = "$releaseRoot\net40"
$buildBase = "$baseDir\build"
$sourceDir = "$baseDir"
$outDir =  "$buildBase\output"
$toolsDir = "$baseDir\tools"
$binariesDir = "$baseDir\binaries"
$ilMergeTool = "$toolsDir\ILMerge\ILMerge.exe"
$nugetExec = "$toolsDir\NuGet\NuGet.exe"
$script:msBuild = ""
$script:isEnvironmentInitialized = $false
$script:ilmergeTargetFramework = ""
$script:msBuildTargetFramework = ""	
$script:packageVersion = "0.1.1.6"
$nunitexec = "packages\NUnit.Runners.lite.2.6.0.12051\nunit-console.exe"
$script:nunitTargetFramework = "/framework=4.0";

include $toolsDir\psake\buildutils.ps1

task default -depends Release

task Clean {
	delete-directory $binariesDir -ErrorAction silentlycontinue
}

task Init -depends Clean {
	create-directory $binariesDir
}

task DetectOperatingSystemArchitecture {
	$isWow64 = ((Get-WmiObject -class "Win32_Processor" -property "AddressWidth").AddressWidth -eq 64)
	if ($isWow64 -eq $true)
	{
		$script:architecture = "x64"
	}
    echo "Machine Architecture is $script:architecture"
}

task InstallDependentPackages {
	cd "$baseDir\packages"
	$files =  dir -Exclude *.config
	cd $baseDir
	$installDependentPackages = $DownloadDependentPackages;
	if($installDependentPackages -eq $false){
		$installDependentPackages = ((($files -ne $null) -and ($files.count -gt 0)) -eq $false)
	}
	if($installDependentPackages){
	 	dir -recurse -include ('packages.config') |ForEach-Object {
		$packageconfig = [io.path]::Combine($_.directory,$_.name)

		write-host $packageconfig 

		 exec{ &$nugetExec install $packageconfig -o packages } 
		}
	}
 }
 
task InitEnvironment -depends DetectOperatingSystemArchitecture {

	if($script:isEnvironmentInitialized -ne $true){
		if ($TargetFramework -eq "net-4.0"){
			$netfxInstallroot ="" 
			$netfxInstallroot =	Get-RegistryValue 'HKLM:\SOFTWARE\Microsoft\.NETFramework\' 'InstallRoot' 
			
			$netfxCurrent = $netfxInstallroot + "v4.0.30319"
			
			$script:msBuild = $netfxCurrent + "\msbuild.exe"
			
			echo ".Net 4.0 build requested - $script:msBuild" 
		
			
			$programFilesPath = (gc env:ProgramFiles)
			if($script:architecture -eq "x64") {
				$programFilesPath = (gc env:"ProgramFiles(x86)")
			}
			
			$frameworkPath = Join-Path $programFilesPath "Reference Assemblies\Microsoft\Framework\.NETFramework\v4.0"
			
			$script:ilmergeTargetFramework  =  "v4,$frameworkPath"
			$script:msBuildTargetFramework ="/p:TargetFrameworkVersion=v4.0 /ToolsVersion:4.0"
			
			$script:nunitTargetFramework = "/framework=4.0";
			
			$script:isEnvironmentInitialized = $true
		}
	
	}
}
 
task CompileMain -depends InstallDependentPackages, InitEnvironment, Init {
 	$solutionFile = "Bouncer.sln"
	exec { &$script:msBuild $solutionFile /p:OutDir="$buildBase\" }
	
	#Copy-Item "$buildBase\Bouncer.dll" $binariesDir
		
	$assemblies = @()
	$assemblies +=	dir $buildBase\Bouncer.dll
	$assemblies  +=  dir $buildBase\Newtonsoft.Json.dll

	& $ilMergeTool /target:"dll" /out:"$binariesDir\Bouncer.dll" /internalize /targetplatform:"$script:ilmergeTargetFramework" /log:"$buildBase\BouncerMergeLog.txt" $assemblies
	$mergeLogContent = Get-Content "$buildBase\BouncerMergeLog.txt"
	echo "------------------------------Bouncer Merge Log-----------------------"
	echo $mergeLogContent
 }
 
 task TestMain -depends CompileMain {

	if((Test-Path -Path $buildBase\test-reports) -eq $false){
		Create-Directory $buildBase\test-reports 
	}
	$testAssemblies = @()
	$testAssemblies +=  dir $buildBase\*Tests.dll
	exec {&$nunitexec $testAssemblies $script:nunitTargetFramework}
}

task PrepareRelease -depends CompileMain, TestMain {
	
	if((Test-Path $releaseRoot) -eq $true){
		Delete-Directory $releaseRoot	
	}
	
	Create-Directory $releaseRoot
	if ($TargetFramework -eq "net-4.0"){
		$releaseDir = "$releaseRoot\net40"
	}
	Create-Directory $releaseDir
	
	Copy-Item -Force -Recurse "$baseDir\binaries" $releaseDir\binaries -ErrorAction SilentlyContinue  
}
 
task CreatePackages -depends PrepareRelease  {

	if(($UploadPackage) -and ($NugetKey -eq "")){
		throw "Could not find the NuGet access key Package Cannot be uploaded without access key"
	}
		
	import-module $toolsDir\NuGet\packit.psm1
	Write-Output "Loading the module for packing.............."
	$packit.push_to_nuget = $UploadPackage 
	$packit.nugetKey  = $NugetKey
	
	$packit.framework_Isolated_Binaries_Loc = "$baseDir\release"
	$packit.PackagingArtifactsRoot = "$baseDir\release\PackagingArtifacts"
	$packit.packageOutPutDir = "$baseDir\release\packages"
	$packit.targeted_Frameworks = "net40";

	#region Packing
	$packageName = "BouncerUtil"
	$packit.package_description = "A utility for selectively enabling features in .NET. Similar to Facebooks GateKeeper."
	invoke-packit $packageName $script:packageVersion @{} "binaries\Bouncer.dll" @{} 
	#endregion
		
	remove-module packit
 } 

task Release -depends CreatePackages {
 
 }

