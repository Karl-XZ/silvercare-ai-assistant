"""Build with an optional test-only credential; never embed that credential in the APK."""
from pathlib import Path
import os, subprocess, sys

root = Path(__file__).resolve().parents[1]
env = os.environ.copy()
env['JAVA_HOME'] = env.get('JAVA_HOME', 'F:/java')
env['PATH'] = env['JAVA_HOME'] + '/bin;' + env['PATH']
env['DASHSCOPE_API_KEY'] = ''
if len(sys.argv) > 1:
    for line in Path(sys.argv[1]).read_text(encoding='utf-8-sig').splitlines():
        if line.startswith('DASHSCOPE_API_KEY='):
            env['SILVERCARE_I18N_TEST_KEY'] = line.split('=', 1)[1].strip().strip('\"\'')
env['SILVERCARE_I18N_TEST_OUT'] = str(root / 'reports/i18n-20261105/live-cloud')
with (root / 'multilingual-final-build.log').open('w', encoding='utf-8') as log:
    result = subprocess.run(['cmd', '/c', 'gradlew.bat', ':app:testDebugUnitTest', ':app:assembleDebug',
                             '--offline', '--max-workers=3', '--console=plain'],
                            cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
print('Gradle exit', result.returncode)
sys.exit(result.returncode)
