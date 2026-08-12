param(
    [string]$KnowledgePath = ".knowledge",
    [string]$VectorStoreName = "mysterious-island-book",
    [string]$VectorStoreEnvName = "MYSTERIOUS_ISLAND_VECTOR_STORE_ID",
    [switch]$ForceNewVectorStore,
    [switch]$SkipAzdEnvSet
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$VenvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$KnowledgeFullPath = Join-Path $ProjectRoot $KnowledgePath

Set-Location $ProjectRoot

if (-not (Test-Path $VenvPython)) {
    throw "Expected virtual environment Python was not found at $VenvPython. Run scripts/setup-dev.ps1 first."
}

if (-not (Test-Path $KnowledgeFullPath)) {
    throw "Knowledge path was not found at $KnowledgeFullPath."
}

function Read-AzdEnvValue {
    param([string]$Name)

    $EnvPath = Get-AzdEnvPath
    if (-not $EnvPath) {
        return $null
    }

    foreach ($Line in Get-Content -LiteralPath $EnvPath) {
        if ($Line -match "^\s*$([regex]::Escape($Name))=(.*)$") {
            return $Matches[1].Trim().Trim('"')
        }
    }

    return $null
}

function Get-AzdEnvPath {
    $AzdConfigPath = Join-Path $ProjectRoot ".azure\config.json"
    if (-not (Test-Path $AzdConfigPath)) {
        return $null
    }

    $AzdConfig = Get-Content -LiteralPath $AzdConfigPath -Raw | ConvertFrom-Json
    if (-not $AzdConfig.defaultEnvironment) {
        return $null
    }

    $EnvPath = Join-Path $ProjectRoot ".azure\$($AzdConfig.defaultEnvironment)\.env"
    if (-not (Test-Path $EnvPath)) {
        return $null
    }

    return $EnvPath
}

function Set-LocalAzdEnvValue {
    param(
        [string]$Name,
        [string]$Value
    )

    $EnvPath = Get-AzdEnvPath
    if (-not $EnvPath) {
        Write-Warning "Could not find a local azd .env file to update."
        return
    }

    $Replacement = "$Name=`"$Value`""
    $Found = $false
    $Lines = foreach ($Line in Get-Content -LiteralPath $EnvPath) {
        if ($Line -match "^\s*$([regex]::Escape($Name))=") {
            $Found = $true
            $Replacement
        } else {
            $Line
        }
    }

    if (-not $Found) {
        $Lines += $Replacement
    }

    Set-Content -LiteralPath $EnvPath -Value $Lines
    Write-Output "Updated local azd environment file: $EnvPath"
}

$ProjectEndpoint = $env:FOUNDRY_PROJECT_ENDPOINT
if (-not $ProjectEndpoint) {
    $ProjectEndpoint = Read-AzdEnvValue "FOUNDRY_PROJECT_ENDPOINT"
}

if (-not $ProjectEndpoint) {
    $ProjectEndpoint = Read-AzdEnvValue "AZURE_AI_PROJECT_ENDPOINT"
}

if (-not $ProjectEndpoint) {
    $ProjectEndpoint = Read-AzdEnvValue "AZURE_AIPROJECT_ENDPOINT"
}

if (-not $ProjectEndpoint) {
    throw "Could not find a Foundry project endpoint. Set FOUNDRY_PROJECT_ENDPOINT or run azd provision/deploy first."
}

$ExistingVectorStoreId = [Environment]::GetEnvironmentVariable($VectorStoreEnvName)
if (-not $ExistingVectorStoreId) {
    $ExistingVectorStoreId = Read-AzdEnvValue $VectorStoreEnvName
}

if ($ForceNewVectorStore) {
    $ExistingVectorStoreId = ""
}

$env:FOUNDRY_PROJECT_ENDPOINT = $ProjectEndpoint
$env:KNOWLEDGE_PATH = $KnowledgeFullPath
$env:KNOWLEDGE_VECTOR_STORE_NAME = $VectorStoreName
$env:KNOWLEDGE_VECTOR_STORE_ID = $ExistingVectorStoreId

$PythonScript = @'
import os
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential


project_endpoint = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
knowledge_path = Path(os.environ["KNOWLEDGE_PATH"])
vector_store_name = os.environ["KNOWLEDGE_VECTOR_STORE_NAME"]
vector_store_id = os.environ.get("KNOWLEDGE_VECTOR_STORE_ID") or None

project = AIProjectClient(
    endpoint=project_endpoint,
    credential=DefaultAzureCredential(),
)
openai = project.get_openai_client()

if vector_store_id:
    vector_store = openai.vector_stores.retrieve(vector_store_id)
else:
    vector_store = openai.vector_stores.create(name=vector_store_name)

if knowledge_path.is_dir():
    knowledge_file_paths = sorted(knowledge_path.glob("*.txt"))
else:
    knowledge_file_paths = [knowledge_path]

if not knowledge_file_paths:
    raise RuntimeError(f"No .txt knowledge files found at {knowledge_path}")

existing_file_names = set()
for vector_store_file in openai.vector_stores.files.list(vector_store.id):
    foundry_file = openai.files.retrieve(vector_store_file.id)
    existing_file_names.add(foundry_file.filename)

print(f"Vector store: {vector_store.id}")

for knowledge_file_path in knowledge_file_paths:
    if knowledge_file_path.name in existing_file_names:
        print(f"Skipping existing file: {knowledge_file_path.name}")
        continue

    print(f"Uploading: {knowledge_file_path}")
    with knowledge_file_path.open("rb") as file_handle:
        uploaded = openai.vector_stores.files.upload_and_poll(
            vector_store_id=vector_store.id,
            file=file_handle,
        )

    print(f"Vector store file: {uploaded.id}")
    print(f"Vector store file status: {uploaded.status}")

print(f"::vector_store_id::{vector_store.id}")
'@

$Output = $PythonScript | & $VenvPython -
if ($LASTEXITCODE -ne 0) {
    throw "Knowledge upload failed with exit code $LASTEXITCODE."
}

$Output | ForEach-Object { Write-Output $_ }

$VectorStoreId = $null
foreach ($Line in $Output) {
    if ($Line -match "^::vector_store_id::(.+)$") {
        $VectorStoreId = $Matches[1].Trim()
    }
}

if (-not $VectorStoreId) {
    throw "Knowledge upload completed, but the vector store ID was not found in the script output."
}

if (-not $SkipAzdEnvSet) {
    $AzdCommand = Get-Command azd -ErrorAction SilentlyContinue
    if ($AzdCommand) {
        & azd env set $VectorStoreEnvName $VectorStoreId
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "azd env set failed with exit code $LASTEXITCODE. Updating the local azd .env file instead."
            Set-LocalAzdEnvValue $VectorStoreEnvName $VectorStoreId
        }
    } else {
        Write-Warning "azd was not found on PATH. Updating the local azd .env file instead."
        Set-LocalAzdEnvValue $VectorStoreEnvName $VectorStoreId
    }
}

Write-Output "Knowledge vector store ID: $VectorStoreId"
