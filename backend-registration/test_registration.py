import os,tempfile,unittest,threading,json,urllib.request,urllib.error,datetime as dt
from pathlib import Path
with tempfile.TemporaryDirectory() as directory:
 os.environ['RV_DB']=directory+'/test.sqlite';os.environ['RV_TEST_OUTBOX']=directory+'/mail'
 for name in ('ADMIN','CLIENT1','CLIENT2'):os.environ['RV_'+name+'_PASSWORD']='Test-'+name+'-123456'
 import server as s
 s.init();srv=s.ThreadingHTTPServer(('127.0.0.1',0),s.Handler);threading.Thread(target=srv.serve_forever,daemon=True).start()
 def api(path,body=None,token=None):
  req=urllib.request.Request(f'http://127.0.0.1:{srv.server_port}/api/'+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+(token or '')})
  try:
   with urllib.request.urlopen(req) as r:return r.status,json.load(r)
  except urllib.error.HTTPError as e:return e.code,json.load(e)
 class Tests(unittest.TestCase):
  def test_registration_lifecycle(self):
   data={'given':'Jean','family':'Test','phone':'0000000000','email':'jean@example.test','password':'Test123456789','role':'admin'};login={'login':data['email'],'password':data['password']}
   self.assertEqual(api('register',{**data,'email':'test@example.com'})[0],400)
   self.assertEqual(api('register',data),(200,{'verification_required':True}));self.assertEqual(api('register',data)[0],409);self.assertEqual(api('login',login)[0],403)
   mail=json.loads(next(Path(os.environ['RV_TEST_OUTBOX']).glob('*.json')).read_text());self.assertEqual(mail['to'],data['email']);v={'email':data['email'],'token':mail['verification_token']}
   self.assertEqual(api('verify-email',{**v,'token':'fake'})[0],400);self.assertEqual(api('verify-email',v)[0],200);self.assertEqual(api('verify-email',v)[0],400)
   status,session=api('login',login);self.assertEqual(status,200);self.assertEqual(session['user']['role'],'client');token=session['token'];self.assertEqual(api('clients',token=token)[0],403)
   day=dt.datetime.now(s.ZONE).date()+dt.timedelta(days=1)
   while day.weekday()>=5:day+=dt.timedelta(days=1)
   status,b=api('book',{'kind':'maintenance','day':day.isoformat(),'start':540},token);self.assertEqual(status,200)
   admin=api('login',{'login':'admin','password':'Test-ADMIN-123456'})[1]['token'];a=next(a for a in api('appointments',token=admin)[1] if a['id']==b['id']);self.assertEqual((a['given'],a['family'],a['email'],a['phone']),('Jean','Test',data['email'],data['phone']))
   other=api('login',{'login':'client2','password':'Test-CLIENT2-123456'})[1]['token'];self.assertEqual(api('appointments',token=other)[1],[])
 result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests));srv.shutdown();raise SystemExit(not result.wasSuccessful())
