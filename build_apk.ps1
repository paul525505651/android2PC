# Config Paths
$SDK_ROOT = "C:\Users\Admin\Desktop\software\android_sdk"
$BUILD_TOOLS_VERSION = "34.0.0"
$PLATFORM_VERSION = "android-35"

$BUILD_TOOLS = "$SDK_ROOT\build-tools\$BUILD_TOOLS_VERSION"
$PLATFORM = "$SDK_ROOT\platforms\$PLATFORM_VERSION\android.jar"

# Tool Paths
$AAPT2 = "$BUILD_TOOLS\aapt2.exe"
$D8 = "$BUILD_TOOLS\d8.bat"
$APKSIGNER = "$BUILD_TOOLS\apksigner.bat"
$ZIPALIGN = "$BUILD_TOOLS\zipalign.exe"

# Check Tools
if (-not (Test-Path $AAPT2)) { Write-Error "Error: aapt2 not found at $AAPT2"; exit 1 }
if (-not (Test-Path $PLATFORM)) { Write-Error "Error: android.jar not found at $PLATFORM"; exit 1 }

# Prepare Directories
$SRC = "Android_Source"
$OBJ = "$SRC\obj"
$BIN = "$SRC\bin"
$GEN = "$SRC\gen"

if (Test-Path $OBJ) { Remove-Item $OBJ -Recurse -Force }
if (Test-Path $BIN) { Remove-Item $BIN -Recurse -Force }
if (Test-Path $GEN) { Remove-Item $GEN -Recurse -Force }

New-Item -ItemType Directory -Force -Path $OBJ | Out-Null
New-Item -ItemType Directory -Force -Path $BIN | Out-Null
New-Item -ItemType Directory -Force -Path $GEN | Out-Null

Write-Host "1. Compiling resources (aapt2 compile)..." -ForegroundColor Cyan
Get-ChildItem -Path "$SRC\res" -Recurse -Include *.xml,*.png | ForEach-Object {
    & $AAPT2 compile --dir "$SRC\res" -o "$OBJ\res.zip"
}

Write-Host "2. Linking resources (aapt2 link)..." -ForegroundColor Cyan
& $AAPT2 link -o "$SRC\bin\unaligned.apk" -I $PLATFORM --manifest "$SRC\AndroidManifest.xml" --java $GEN --auto-add-overlay "$OBJ\res.zip"

if (-not (Test-Path "$SRC\bin\unaligned.apk")) {
    Write-Error "Error: aapt2 link failed."
    exit 1
}

Write-Host "3. Compiling Java (javac)..." -ForegroundColor Cyan
$javaFiles = @()
$javaFiles += Get-ChildItem -Path "$SRC\src" -Recurse -Include *.java | Select-Object -ExpandProperty FullName
$javaFiles += Get-ChildItem -Path "$GEN" -Recurse -Include *.java | Select-Object -ExpandProperty FullName

if ($javaFiles -is [string]) { $javaFiles = @($javaFiles) }

$javaFileList = ""
foreach ($file in $javaFiles) {
    $javaFileList += " `"$file`""
}

Write-Host "Java files: $javaFileList" -ForegroundColor DarkGray
cmd /c "javac -d ""$OBJ"" -classpath ""$PLATFORM"" $javaFileList"

if (-not (Get-ChildItem -Path $OBJ -Recurse -Include *.class)) {
    Write-Error "Error: Java compilation failed (no .class files found)."
    exit 1
}

Write-Host "4. Converting to Dex (d8)..." -ForegroundColor Cyan
$classFiles = Get-ChildItem -Path $OBJ -Recurse -Include *.class | Select-Object -ExpandProperty FullName
& $D8 --output $BIN --lib $PLATFORM $classFiles

Write-Host "5. Adding classes.dex to APK..." -ForegroundColor Cyan
if (-not (Test-Path "$SRC\bin\classes.dex")) {
    Write-Error "Error: classes.dex not found."
    exit 1
}

$apkPath = "$SRC\bin\unaligned.apk"
$dexPath = "$SRC\bin\classes.dex"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    # Open with string "Update" instead of Enum
    $zip = [System.IO.Compression.ZipFile]::Open($apkPath, "Update")
    $entry = $zip.GetEntry("classes.dex")
    if ($entry) { $entry.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $dexPath, "classes.dex")
    $zip.Dispose()
    Write-Host "classes.dex added successfully." -ForegroundColor Green
}
catch {
    Write-Error "Error adding classes.dex: $_"
    exit 1
}

Write-Host "6. Aligning APK (zipalign)..." -ForegroundColor Cyan
if (Test-Path $ZIPALIGN) {
    & $ZIPALIGN -f -p 4 "$SRC\bin\unaligned.apk" "$SRC\bin\aligned.apk"
} else {
    Write-Warning "zipalign not found, skipping..."
    Copy-Item "$SRC\bin\unaligned.apk" "$SRC\bin\aligned.apk"
}

if (-not (Test-Path "$SRC\bin\aligned.apk")) {
    Write-Error "Error: aligned.apk not found."
    exit 1
}

Write-Host "7. Signing APK (debug key)..." -ForegroundColor Cyan
# 使用固定的 keystore，避免每次清理 bin 后重新生成导致无法覆盖安装
$KEYSTORE = "$SRC\keystore.jks"

if (-not (Test-Path $KEYSTORE)) {
    Write-Host "Generating new keystore at $KEYSTORE..." -ForegroundColor Yellow
    try {
        & keytool -genkey -v -keystore $KEYSTORE -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    } catch {
        Write-Warning "Warning: keytool failed, signing might fail."
    }
} else {
    Write-Host "Using existing keystore: $KEYSTORE" -ForegroundColor Gray
}

& cmd /c "$APKSIGNER" sign --ks $KEYSTORE --ks-pass pass:android --key-pass pass:android --out "$SRC\Android2PC.apk" "$SRC\bin\aligned.apk"

if (Test-Path "$SRC\Android2PC.apk") {
    Write-Host "=== BUILD SUCCESS! APK: $SRC\Android2PC.apk ===" -ForegroundColor Green
} else {
    Write-Error "Error: Final APK not created."
    exit 1
}
