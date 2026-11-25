from pathlib import Path
import shutil,sys
p=Path(sys.argv[1]);s=p.read_text()
def replace(old,new):
 global s
 assert s.count(old)==1,old
 s=s.replace(old,new)
replace('from zoneinfo import ZoneInfo','from zoneinfo import ZoneInfo\nimport registration')
replace("  for name,role in [('admin','admin')", "  registration.schema(c)\n  for name,role in [('admin','admin')")
replace("   if p.path=='/api/login' and method=='POST':", "   if p.path=='/api/register' and method=='POST': result=registration.register(c,d,require,uid,password)\n   elif p.path=='/api/verify-email' and method=='POST': result=registration.verify(c,d,require)\n   elif p.path=='/api/login' and method=='POST':")
replace("token=secrets.token_urlsafe(32); c.execute('INSERT INTO sessions", "profile=c.execute('SELECT verified FROM profiles WHERE user=?',(u['id'],)).fetchone(); require(not profile or profile['verified']==1,403,'Confirmez votre e-mail'); token=secrets.token_urlsafe(32); c.execute('INSERT INTO sessions")
replace("if admin: return rows(c,'SELECT * FROM appointments ORDER BY day,start')", "if admin: return rows(c,'SELECT a.*,u.name AS client_name,p.given,p.family,p.email,p.phone FROM appointments a JOIN users u ON u.id=a.client LEFT JOIN profiles p ON p.user=u.id ORDER BY day,start')")
p.write_text(s);shutil.copyfile(Path(__file__).with_name('registration.py'),p.with_name('registration.py'))
