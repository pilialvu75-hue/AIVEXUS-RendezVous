/* RendezVous 0.2.2 UI preview. Fictional data only. */
(() => {
  const el=document.getElementById('view');
  const oldBook=book, oldAgenda=agenda, oldSettings=settings, oldEntry=entry;
  const fmt=(y,m,d)=>[y,String(m+1).padStart(2,'0'),String(d).padStart(2,'0')].join('-');
  const getProfile=()=>db.profile||null;
  const emailOK=s=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
  const clean=s=>String(s??'').trim();
  function monthView(admin){
    let [y,m]=date.split('-').map(Number);m--;
    const first=new Date(y,m,1,12), offset=(first.getDay()+6)%7;
    const last=new Date(y,m+1,0,12).getDate();
    const t=db.types.find(x=>x.id===kind)||db.types[0];
    const days=Array.from({length:offset},()=>'<span></span>');
    for(let d=1;d<=last;d++){
      const key=fmt(y,m,d), closed=key<dateNow()||!db.days.includes(new Date(y,m,d,12).getDay());
      const n=db.appointments.filter(a=>a.date===key&&a.status!=='cancelled').length;
      const free=Core.slots(db,key,t.duration,editing).length>0;
      const state=admin?(n?'rv-busy':closed?'rv-closed':'rv-free'):(closed?'rv-closed':free?'rv-free':'rv-full');
      const label=key+(admin?' : '+n+' rendez-vous':closed?' : fermé':free?' : disponible':' : complet');
      days.push('<button class="rv-day '+state+(key===date?' rv-selected':'')+'" aria-label="'+E(label)+'" '+(!admin&&(closed||!free)?'disabled':'')+' data-day="'+key+'">'+d+(admin&&n?'<small>'+n+' RDV</small>':'')+'</button>');
    }
    const title=new Intl.DateTimeFormat('fr-FR',{month:'long',year:'numeric'}).format(first);
    const box=document.createElement('section');box.className='card rv-month';
    box.innerHTML='<div class="rv-heading"><button class="secondary" data-month="-1" aria-label="Mois précédent">‹</button><strong>'+E(title)+'</strong><button class="secondary" data-month="1" aria-label="Mois suivant">›</button></div><div class="rv-grid">'+['Lun','Mar','Mer','Jeu','Ven','Sam','Dim'].map(x=>'<span class="rv-week">'+x+'</span>').join('')+days.join('')+'</div><p class="muted">'+(admin?'Bleu : rendez-vous · Vert : ouvert · Gris : fermé/passé':'Vert foncé : disponible · Rouge foncé : complet · Gris : fermé/passé')+'</p>';
    box.querySelectorAll('[data-day]').forEach(b=>b.onclick=()=>{date=b.dataset.day;chosen=null;render()});
    box.querySelectorAll('[data-month]').forEach(b=>b.onclick=()=>{const n=new Date(y,m+Number(b.dataset.month),1,12);date=fmt(n.getFullYear(),n.getMonth(),1);chosen=null;render()});
    return box;
  }
  function profileForm(){
    const p=getProfile()||{};
    const box=document.createElement('div');box.className='card';
    box.innerHTML='<h2>Identification du client (démo locale)</h2><p class="muted">Aucun compte vérifié : utilisez uniquement des coordonnées fictives.</p>'+
      [['family','Nom'],['given','Prénom'],['email','Adresse e-mail'],['phone','Téléphone']].map(([k,l])=>'<label for="rv-'+k+'">'+l+' *</label><input id="rv-'+k+'" maxlength="120" value="'+E(p[k]||'')+'" '+(k==='email'?'type="email"':k==='phone'?'type="tel"':'')+'>').join('')+
      '<button id="rv-profile-save" class="secondary">Enregistrer mon profil</button>';
    box.querySelector('#rv-profile-save').onclick=()=>{const profile=readProfile();if(profile&&update(()=>db.profile=profile))toast('Profil fictif enregistré.')};
    return box;
  }
  function readProfile(){
    const p={};for(const k of ['family','given','email','phone'])p[k]=clean(document.getElementById('rv-'+k)?.value);
    if(!p.family||!p.given||!emailOK(p.email)||!p.phone){toast('Renseignez nom, prénom, e-mail et téléphone.');return null}
    return p;
  }
  book=function(){
    oldBook();
    const input=document.getElementById('date');
    if(input){const lab=input.previousElementSibling;input.replaceWith(monthView(false));if(lab)lab.remove()}
    const c=document.getElementById('confirm');
    if(c&&chosen!==null&&!editing){const n=document.getElementById('name');if(n){n.previousElementSibling?.remove();n.remove()}c.insertBefore(profileForm(),c.querySelector('label[for=attach]')||c.firstChild)}
  };
  confirmBook=async function(){
    const t=db.types.find(x=>x.id===kind),sel=chosen,d=date,id=editing;
    const existing=db.appointments.find(a=>a.id===id);
    const p=existing?existing.profile:readProfile();if(!existing&&!p)return;
    if(sel===null||!t)return toast('Sélectionnez un créneau.');
    let f;try{f=await readFile(document.getElementById('attach')?.files[0])}catch(e){return toast(e.message)}
    const a={id:id||uid(),client:existing?.client||client,name:existing?.name||p.given+' '+p.family,profile:p||null,type:t.id,duration:existing?.duration||t.duration,date:d,start:sel,status:'confirmed'};
    if(update(()=>{if(!existing)db.profile=p;Core.reserve(db,a);if(f)db.docs.push({...f,id:uid(),client:a.client,from:role,date:new Date().toISOString(),appointment:a.id});db.messages.push({id:uid(),client:a.client,from:'system',body:'Rendez-vous '+(id?'déplacé':'confirmé')+' : '+d+' à '+Core.hh(sel)+'.',date:new Date().toISOString()})})){toast('Rendez-vous enregistré.');go(role==='admin'?'agenda':'mine')}
  };
  function row(a){const p=a.profile||{};return [a.date,Core.hh(a.start),Core.hh(a.start+a.duration),p.family||a.name,p.given||'',p.phone||'',p.email||'',db.types.find(t=>t.id===a.type)?.name||a.type,a.duration,a.status==='cancelled'?'Annulé':'Confirmé',db.docs.filter(d=>d.appointment===a.id).length]}
  const headers=['Date','Début','Fin','Nom','Prénom','Téléphone','E-mail','Motif','Durée (min)','Statut','Documents'];
  const allRows=()=>[headers,...db.appointments.slice().sort((a,b)=>a.date.localeCompare(b.date)||a.start-b.start).map(row)];
  function address(){const a=clean(db.exportEmail);if(!emailOK(a)){toast('Configurez une adresse e-mail dans Réglages.');return null}return a}
  function exportAgenda(){
    if(role!=='admin')return;
    const a=address();if(!a)return;
    if(!window.RVExport)return toast('Partage Android indisponible.');
    if(confirm('Préparer le fichier Excel de tous les rendez-vous fictifs pour '+a+' ?'))window.RVExport.shareExcel(JSON.stringify(allRows()),a);
  }
  function sendAppointment(id){
    if(role!=='admin')return;
    const a=db.appointments.find(x=>x.id===id),to=address();
    if(!a||!to)return;
    const docs=db.docs.filter(d=>d.appointment===id);
    const summary=headers.map((h,i)=>h+' : '+row(a)[i]).join('\n');
    if(!window.RVExport)return toast('Partage Android indisponible.');
    if(confirm('Préparer un e-mail de test pour '+to+' avec '+docs.length+' document(s) fictif(s) ?'))window.RVExport.shareDocuments(JSON.stringify(docs.map(d=>({name:d.name,mime:d.mime,data:d.data.split(',')[1]}))),to,summary);
  }
  entry=function(a){
    const html=oldEntry(a);if(role!=='admin')return html;
    const p=a.profile||{};const docs=db.docs.filter(d=>d.appointment===a.id);
    return html.slice(0,-6)+'<p class="muted">'+E(p.email||'E-mail non renseigné')+' · '+E(p.phone||'Téléphone non renseigné')+'</p><p class="muted">'+docs.length+' document(s)</p><button class="secondary" data-mail-id="'+E(a.id)+'">Envoyer par e-mail</button></div>';
  };
  agenda=function(){
    oldAgenda();
    const input=el.querySelector('input[type=date]');if(input){const lab=input.previousElementSibling;input.replaceWith(monthView(true));lab?.remove()}
    const b=document.createElement('button');b.className='secondary full';b.textContent='Exporter tous les rendez-vous (.xlsx) par e-mail';b.onclick=exportAgenda;el.querySelector('.card')?.append(b);
    el.querySelectorAll('[data-mail-id]').forEach(b=>b.onclick=()=>sendAppointment(b.dataset.mailId));
  };
  settings=function(){
    oldSettings();
    const box=document.createElement('div');box.className='card';
    box.innerHTML='<h2>Export et messagerie</h2><label for="rv-mail">Adresse e-mail destinataire</label><input type="email" id="rv-mail" value="'+E(db.exportEmail||'')+'"><p class="muted">Le partage ouvre une application de messagerie : vérifiez le destinataire, puis confirmez l’envoi. Données fictives uniquement.</p><button id="rv-mail-save">Enregistrer</button>';
    box.querySelector('button').onclick=()=>{const a=clean(box.querySelector('input').value);if(!emailOK(a))return toast('Adresse invalide.');if(update(()=>db.exportEmail=a))toast('Adresse enregistrée.')};
    el.insertBefore(box,el.children[1]||null);
  };
  const style=document.createElement('style');style.textContent='.rv-grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:4px}.rv-day{min-width:0;padding:4px 0;font-size:14px;min-height:44px;border-radius:5px}.rv-day small{display:block;font-size:9px}.rv-heading{display:flex;justify-content:space-between;align-items:center;gap:6px;margin-bottom:10px}.rv-heading strong{text-transform:capitalize}.rv-week{text-align:center;font-size:11px}.rv-free{background:#18552f;color:#fff}.rv-full{background:#791c2b;color:#fff}.rv-closed{background:#535d65;color:#fff}.rv-busy{background:#125566;color:#fff}.rv-day:disabled{opacity:1;cursor:default}.rv-selected{outline:3px solid #d6a128;outline-offset:1px}';
  document.head.append(style);
  render();
})();
