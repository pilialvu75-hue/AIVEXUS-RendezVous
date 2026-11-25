"""Test-only registration service; production transport is deliberately absent."""
import hashlib, hmac, json, os, re, secrets, time
from pathlib import Path

def schema(c):
 c.executescript('''CREATE TABLE IF NOT EXISTS profiles(user TEXT PRIMARY KEY REFERENCES users(id),given TEXT NOT NULL,family TEXT NOT NULL,email TEXT UNIQUE NOT NULL,phone TEXT NOT NULL,verified INTEGER NOT NULL DEFAULT 0);
 CREATE TABLE IF NOT EXISTS email_verification(user TEXT PRIMARY KEY REFERENCES users(id),digest TEXT NOT NULL,expires INTEGER NOT NULL);''')

def register(c,d,require,uid,password):
 # Fictional test domain only, to prevent accidental use with real clients.
 p={k:d.get(k) for k in ('given','family','email','phone','password')}
 require(all(isinstance(v,str) for v in p.values()),400,'Champs requis')
 given,family,email,phone=(p[k].strip() for k in ('given','family','email','phone')); email=email.lower(); pw=p['password']
 require(0<len(given)<=100 and 0<len(family)<=100 and 0<len(phone)<=40 and len(email)<=254 and bool(re.fullmatch(r'[^\s@]+@[^\s@]+\.test',email)),400,'Coordonnées fictives en .test requises')
 require(12<=len(pw)<=256,400,'Mot de passe : 12 caractères minimum')
 outbox=os.environ.get('RV_TEST_OUTBOX');require(bool(outbox),503,'Transport e-mail de test non configuré')
 # No client-supplied role is accepted.
 require(not c.execute('SELECT 1 FROM users WHERE login=?',(email,)).fetchone(),409,'Compte déjà créé')
 ident=uid(); salt=secrets.token_hex(16); token=secrets.token_urlsafe(32)
 c.execute('INSERT INTO users VALUES(?,?,?,?,?,?)',(ident,given+' '+family,email,'client',salt,password(pw,salt)))
 c.execute('INSERT INTO profiles VALUES(?,?,?,?,?,0)',(ident,given,family,email,phone))
 c.execute('INSERT INTO email_verification VALUES(?,?,?)',(ident,hashlib.sha256(token.encode()).hexdigest(),int(time.time())+900))
 # The harness consumes this synthetic message. No real SMTP or public URL.
 folder=Path(outbox);folder.mkdir(mode=0o700,parents=True,exist_ok=True)
 with os.fdopen(os.open(folder/(ident+'.json'),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'w') as f: json.dump({'to':email,'verification_token':token},f)
 return {'verification_required':True}

def verify(c,d,require):
 email=d.get('email');token=d.get('token')
 require(isinstance(email,str) and isinstance(token,str) and len(email)<=254 and len(token)<=128,400,'Lien invalide')
 row=c.execute('SELECT v.* FROM email_verification v JOIN profiles p ON p.user=v.user WHERE p.email=?',(email.strip().lower(),)).fetchone()
 require(row and row['expires']>=int(time.time()) and hmac.compare_digest(row['digest'],hashlib.sha256(token.encode()).hexdigest()),400,'Lien invalide ou expiré')
 c.execute('UPDATE profiles SET verified=1 WHERE user=?',(row['user'],));c.execute('DELETE FROM email_verification WHERE user=?',(row['user'],))
 return {'verified':True}
