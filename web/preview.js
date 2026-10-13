(() => {
  'use strict';
  // FiveM always uses the real NUI callbacks. The demo has no network adapter.
  if (typeof GetParentResourceName === 'function' || new URLSearchParams(location.search).get('preview') === '0') return;

  const clone = value => JSON.parse(JSON.stringify(value));
  const storageKey = 'aegis-enterprise-preview-v1';
  const rule = () => ({mode:'all', grades:[], identifiers:[]});
  const permissions = () => ({access:0, withdraw:0, store:0, manage:4, fleet_add:3, fleet_remove:4, categories:4, assign_category:3, rename:3, access_rules:rule()});
  const position = (x=401.2, y=-1632.8, z=29.3, h=230) => ({x,y,z,h});
  const vehicle = (id, plate, label, model, stored, category_id) => ({id,plate,label,model,stored,category_id,vehicle_type:'automobile',props:{plate,model,fuelLevel:83,engineHealth:980,bodyHealth:955,color1:28,color2:0}});
  const sampleGarage = (id, name, job, x) => ({id,name,job,entrance:position(x),spawn:position(x+8),permissions:permissions(),interaction:{mode:'marker',pedModel:'s_m_m_security_01',scenario:'WORLD_HUMAN_CLIPBOARD'},
    spawnPoints:[{id:id*10+1,label:'Sortie principale',coords:position(x+8)},{id:id*10+2,label:'Sortie secondaire',coords:position(x+16)}],
    storePoints:[{id:id*10+3,label:'Rangement principal',coords:position(x+3)}],
    categories:[{id:id*10+4,name:'Véhicules de service',access_grade:0,withdraw_grade:0,store_grade:0,access_rules:rule()},{id:id*10+5,name:'Direction',access_grade:4,withdraw_grade:4,store_grade:4,access_rules:rule()}],vehicles:[]});
  function initialData() {
    const workshop=sampleGarage(1,'Atelier · Garage principal','mechanic',401.2);
    workshop.vehicles=[vehicle(1,'AEGIS01','Dépanneuse de service','towtruck',true,14),vehicle(2,'AEGIS02','Sultan · Intervention','sultan',false,14),vehicle(3,'AEGIS03','Schafter · Direction','schafter2',true,15)];
    const police=sampleGarage(2,'Police · Garage central','police',441.4);
    police.vehicles=[vehicle(4,'LSPD001','Patrouille urbaine','police3',true,24),vehicle(5,'LSPD002','Unité banalisée','police4',false,24)];
    return {version:1,nextId:100,garages:[workshop,police],externalVehicles:[
      {...vehicle(90,'OKOK001','Buffalo · Société','buffalo',false,0),owner:'society_mechanic',sourceResource:'okokGarage',parking:'Garage central'},
      {...vehicle(91,'OKOK002','Blista · Personnel','blista',false,0),owner:'demo:alex',sourceResource:'okokGarage',parking:'Garage public'}
    ]};
  }
  let data;
  try {const saved=JSON.parse(localStorage.getItem(storageKey));data=saved?.version===1&&Array.isArray(saved.garages)&&Array.isArray(saved.externalVehicles)?saved:initialData();}
  catch {data=initialData();}
  let role='admin',currentPlate='OKOK001';
  const profiles={admin:{grade:4,isAdmin:true,label:'Alex Martin · Staff'},manager:{grade:4,isAdmin:false,label:'Alex Martin · Responsable'},employee:{grade:1,isAdmin:false,label:'Alex Martin · Employé'}};
  const allowedRule = (grade, minimum, access) => access?.mode==='list' ? (access.grades||[]).includes(grade)||(access.identifiers||[]).includes('demo:alex') : grade>=Number(minimum||0);
  function abilities(g) {
    const profile=profiles[role],access=profile.isAdmin||(g.job==='mechanic'&&allowedRule(profile.grade,g.permissions.access,g.permissions.access_rules));
    const result=Object.fromEntries(Object.entries(g.permissions).filter(([key])=>key!=='access_rules').map(([key,value])=>[key,profile.isAdmin||(access&&profile.grade>=Number(value))]));
    result.access=access;result.structure=profile.isAdmin;return result;
  }
  function categoryAllowed(g,v,action) {
    const category=g.categories.find(c=>c.id===v.category_id),p=profiles[role];
    return p.isAdmin||!category||(allowedRule(p.grade,category.access_grade,category.access_rules)&&p.grade>=Number(category[action+'_grade']||0));
  }
  function bootstrap() {
    const profile=profiles[role];
    return {ok:true,isAdmin:profile.isAdmin,canCreate:profile.isAdmin,singleGarage:!profile.isAdmin,staffView:profile.isAdmin,playerJob:'mechanic',grade:profile.grade,playerLabel:profile.label,
      bridge:{enabled:true,allowEmployeeOwned:true},
      garages:data.garages.filter(g=>abilities(g).access).map(g=>({...clone(g),abilities:abilities(g),vehicles:g.vehicles.filter(v=>categoryAllowed(g,v,'access')).map(v=>({...clone(v),canWithdraw:abilities(g).withdraw&&categoryAllowed(g,v,'withdraw'),canStore:abilities(g).store&&categoryAllowed(g,v,'store')}))}))};
  }
  const failure = error => ({ok:false,error});
  const success = (message,extra={}) => ({ok:true,message,...extra});
  function carried() {return data.externalVehicles.find(v=>v.plate===currentPlate)||data.garages.flatMap(g=>g.vehicles).find(v=>v.plate===currentPlate&&!v.stored);}
  function persist() {try {localStorage.setItem(storageKey,JSON.stringify(data));} catch {} updateCarried();}
  function importVehicle(g,payload) {
    if(!abilities(g).fleet_add)return failure('Ton grade ne permet pas l’ajout de véhicules.');
    const source=carried();
    if(!source||!data.externalVehicles.includes(source))return failure('Ce véhicule est déjà associé à une flotte ou aucun véhicule externe n’est sélectionné.');
    if(source.owner!=='society_'+g.job&&source.owner!=='demo:alex')return failure('Ce véhicule doit appartenir à la société ou à toi.');
    if(g.vehicles.length>=150)return failure('Capacité maximale de la flotte atteinte.');
    const category=Number(payload.categoryId)||0;
    if(category&&(!abilities(g).assign_category||!g.categories.some(c=>c.id===category)))return failure('Catégorie ou autorisation invalide.');
    const id=data.nextId++;
    g.vehicles.push({...clone(source),id,label:payload.label||source.label,stored:true,category_id:category||null,bridge:{owner:source.owner,parking:source.parking,sourceResource:source.sourceResource}});
    data.externalVehicles=data.externalVehicles.filter(v=>v!==source);currentPlate='';
    return success('Véhicule transféré depuis okokGarage et rangé dans la flotte.',{id});
  }
  function releaseVehicle(g,v) {
    if(v.bridge)data.externalVehicles.push({...clone(v),id:data.nextId++,stored:false,owner:v.bridge.owner,parking:v.bridge.parking,sourceResource:v.bridge.sourceResource});
    g.vehicles=g.vehicles.filter(item=>item!==v);
  }
  const actionPermission={updateGarage:'structure',deleteGarage:'structure',updateGaragePermissions:'manage',registerVehicle:'fleet_add',withdraw:'withdraw',recover:'manage',removeVehicle:'fleet_remove',addPoint:'structure',removePoint:'structure',saveCategory:'categories',deleteCategory:'categories',assignCategory:'assign_category',renameVehicle:'rename'};
  function execute(action,payload) {
    const g=data.garages.find(g=>g.id===Number(payload.garageId||payload.id));
    if(action==='listEmployees') {
      if(!profiles[role].isAdmin&&!g)return failure('Garage introuvable.');
      return {ok:true,grades:[0,1,2,3,4].map(grade=>({grade,label:['Apprenti','Employé','Confirmé','Chef d’équipe','Responsable'][grade]})),employees:[{identifier:'demo:alex',name:'Alex Martin',online:true},{identifier:'demo:lea',name:'Léa Dubois',online:true},{identifier:'demo:samir',name:'Samir Petit',online:false}]};
    }
    if(action==='createGarage') {
      if(!profiles[role].isAdmin)return failure('Création réservée au staff serveur.');
      if(!payload.name?.trim()||!payload.job?.trim()||!payload.entrance||!payload.spawn)return failure('Nom, métier et positions obligatoires.');
      const id=data.nextId++,created=sampleGarage(id,payload.name.trim(),payload.job.trim(),payload.entrance.x);
      Object.assign(created,{entrance:clone(payload.entrance),spawn:clone(payload.spawn),permissions:clone(payload.permissions),interaction:clone(payload.interaction),categories:[],vehicles:[]});
      created.storePoints[0].coords=clone(payload.entrance);created.spawnPoints=[{id:data.nextId++,label:'Sortie principale',coords:clone(payload.spawn)}];data.garages.push(created);
      return success('Garage créé avec succès.',{id});
    }
    if(!g)return failure('Garage introuvable.');
    if(!actionPermission[action]||!abilities(g)[actionPermission[action]])return failure('Ton rôle ne permet pas cette action.');
    const v=g.vehicles.find(v=>v.id===Number(payload.vehicleId));
    switch(action) {
      case 'registerVehicle': return importVehicle(g,payload);
      case 'withdraw':
        if(!v?.stored||!categoryAllowed(g,v,'withdraw'))return failure('Sortie non autorisée ou véhicule déjà dehors.');
        if(Number(payload.pointId)&&!g.spawnPoints.some(p=>p.id===Number(payload.pointId)))return failure('Point de sortie introuvable.');
        v.stored=false;currentPlate=v.plate;return success('Véhicule sorti : clés partagées aux employés autorisés.');
      case 'recover':
        if(!v||v.stored)return failure('Véhicule déjà au garage.');
        if(currentPlate===v.plate)return failure('Le véhicule est encore présent. Range-le normalement.');
        v.stored=true;return success('Véhicule absent récupéré dans le garage.');
      case 'removeVehicle':
        if(!v?.stored)return failure('Range le véhicule avant son retrait.');
        releaseVehicle(g,v);return success('Véhicule retiré, propriété et garage d’origine restaurés.');
      case 'renameVehicle':
        if(!v||!payload.label?.trim())return failure('Nom du véhicule obligatoire.');
        v.label=payload.label.trim();return success('Nom du véhicule enregistré.');
      case 'assignCategory':
        if(!v||Number(payload.categoryId)&&!g.categories.some(c=>c.id===Number(payload.categoryId)))return failure('Catégorie introuvable.');
        v.category_id=Number(payload.categoryId)||null;return success('Catégorie enregistrée, clés recalculées.');
      case 'saveCategory': {
        if(!payload.name?.trim())return failure('Nom de catégorie obligatoire.');
        if(payload.grades.access_rules?.mode!=='list'&&(payload.grades.withdraw<payload.grades.access||payload.grades.store<payload.grades.access))return failure('Les grades de sortie et rangement doivent être au moins ceux d’accès.');
        let c=g.categories.find(c=>c.id===Number(payload.categoryId));if(!c){c={id:data.nextId++};g.categories.push(c);}
        Object.assign(c,{name:payload.name.trim(),access_grade:payload.grades.access,withdraw_grade:payload.grades.withdraw,store_grade:payload.grades.store,access_rules:clone(payload.grades.access_rules)});return success('Catégorie enregistrée.');
      }
      case 'deleteCategory':
        g.categories=g.categories.filter(c=>c.id!==Number(payload.categoryId));g.vehicles.forEach(v=>{if(v.category_id===Number(payload.categoryId))v.category_id=null;});return success('Catégorie supprimée, véhicules conservés.');
      case 'updateGaragePermissions':g.permissions=clone(payload.permissions);return success('Permissions enregistrées, clés recalculées.');
      case 'updateGarage':Object.assign(g,{name:payload.name,job:payload.job,entrance:clone(payload.entrance),permissions:clone(payload.permissions),interaction:clone(payload.interaction)});return success('Configuration du garage enregistrée.');
      case 'addPoint':
        if(!['spawn','store'].includes(payload.kind)||!payload.coords||!payload.label?.trim())return failure('Point invalide.');
        g[payload.kind+'Points'].push({id:data.nextId++,label:payload.label.trim(),coords:clone(payload.coords)});return success('Point ajouté.');
      case 'removePoint': {
        const key=['storePoints','spawnPoints'].find(key=>g[key].some(p=>p.id===Number(payload.pointId)));
        if(!key||g[key].length===1)return failure('Conserve au moins un point de chaque type.');
        g[key]=g[key].filter(p=>p.id!==Number(payload.pointId));return success('Point supprimé.');
      }
      case 'deleteGarage':
        if(g.vehicles.some(v=>!v.stored))return failure('Tous les véhicules doivent être rangés avant suppression.');
        [...g.vehicles].forEach(v=>releaseVehicle(g,v));data.garages=data.garages.filter(item=>item!==g);return success('Garage supprimé, véhicules externes rendus à leur propriétaire.');
      default:return failure('Action inconnue.');
    }
  }
  async function request(name,payload={}) {
    let response;
    switch(name) {
      case 'fetchData':return bootstrap();
      case 'close':return {ok:true};
      case 'capturePosition':case 'selectPosition':return {ok:true,position:position(401.2+data.nextId%20,-1632.8+data.nextId%10)};
      case 'captureVehicle': {
        const v=carried();return v?{ok:true,netId:v.id,plate:v.plate,label:v.label,vehicleType:v.vehicle_type,props:clone(v.props)}:failure('Choisis un véhicule au volant dans la barre de démonstration.');
      }
      case 'execute':response=execute(payload.action,payload.data||{});break;
      case 'storeCurrent': {
        const g=data.garages.find(g=>g.id===Number(payload.garageId)),v=carried();
        if(!g||!abilities(g).store){response=failure('Rangement non autorisé.');break;}
        if(!v){response=failure('Choisis un véhicule au volant dans la barre de démonstration.');break;}
        if(data.externalVehicles.includes(v)) {
          response=payload.vehicleId?failure('Tu n’es pas au volant du véhicule sélectionné.'):importVehicle(g,{label:v.label});break;
        }
        if(!g.vehicles.includes(v)||payload.vehicleId&&v.id!==Number(payload.vehicleId)||!categoryAllowed(g,v,'store')){response=failure('Ce véhicule ne correspond pas à une sortie autorisée de ce garage.');break;}
        v.stored=true;currentPlate='';response=success('Véhicule rangé, propriétés enregistrées et clés révoquées.');break;
      }
      default:return failure('Action de démonstration inconnue.');
    }
    if(response.ok)persist();return response;
  }
  function open() {
    window.dispatchEvent(new MessageEvent('message',{data:{type:'open'}}));
    window.dispatchEvent(new MessageEvent('message',{data:{type:'bootstrap',payload:bootstrap()}}));
  }
  const bar=document.createElement('aside');bar.className='preview-bar';bar.setAttribute('aria-label','Commandes de démonstration');
  bar.innerHTML='<strong>DÉMONSTRATION <span>Données fictives · actions simulées</span></strong><label>Rôle <select id="preview-role"><option value="admin">Staff</option><option value="manager">Responsable</option><option value="employee">Employé</option></select></label><label>Au volant <select id="preview-vehicle"></select></label><button type="button" id="preview-open">Ouvrir</button><button type="button" id="preview-reset">Réinitialiser</button>';
  document.body.classList.add('preview-mode');document.body.prepend(bar);
  const selector=bar.querySelector('#preview-vehicle');
  function updateCarried() {
    selector.replaceChildren(new Option('Aucun véhicule',''));
    for(const v of [...data.externalVehicles,...data.garages.flatMap(g=>g.vehicles).filter(v=>!v.stored)])selector.add(new Option(v.plate+' · '+v.label+(data.externalVehicles.includes(v)?' · okokGarage':''),v.plate));
    selector.value=currentPlate;if(selector.value!==currentPlate)currentPlate='';
  }
  bar.querySelector('#preview-role').addEventListener('change',event=>{role=event.target.value;open();});
  selector.addEventListener('change',()=>{currentPlate=selector.value;});
  bar.querySelector('#preview-open').addEventListener('click',open);
  bar.querySelector('#preview-reset').addEventListener('click',()=>{data=initialData();currentPlate='OKOK001';role='admin';bar.querySelector('#preview-role').value=role;persist();open();});
  updateCarried();window.EnterpriseGaragePreview={request,bootstrap,open};
})();
