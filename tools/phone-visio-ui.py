"""ADB UI evidence helper for the connected acceptance phone."""
import os, subprocess, sys, xml.etree.ElementTree as ET
from pathlib import Path
adb='C:/Users/Mariya/AppData/Local/Android/sdk/platform-tools/adb.exe'
out=Path(__file__).resolve().parents[1]/'artifacts/vessel-constructor-v2'
def run(*args):return subprocess.run([adb,'-s',os.environ.get('ANDROID_SERIAL', '192.168.3.4:34327'),*args],check=True,capture_output=True,timeout=20)
if len(sys.argv)>1:
    if sys.argv[1]=='tap':run('shell','input','tap',sys.argv[2],sys.argv[3])
    elif sys.argv[1]=='back':run('shell','input','keyevent','4')
    elif sys.argv[1]=='text':run('shell','input','text',sys.argv[2])
    elif sys.argv[1]=='swipe':run('shell','input','swipe',*sys.argv[2:6],'400')
run('shell','uiautomator','dump','/sdcard/visio-ui.xml')
run('pull','/sdcard/visio-ui.xml',str(out/'visio-ui.xml'))
for n in ET.parse(out/'visio-ui.xml').iter('node'):
    label=n.get('text') or n.get('content-desc')
    if label:print(label.replace('\n',' | '),n.get('bounds'))
if len(sys.argv)>1 and sys.argv[1]=='shot':
    run('shell','screencap','-p','/sdcard/visio-phone.png')
    run('pull','/sdcard/visio-phone.png',str(out/(sys.argv[2]+'.png')))
