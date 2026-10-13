(() => {
  'use strict';
  const IS_FIVEM = typeof GetParentResourceName === 'function';
  const resource = IS_FIVEM ? GetParentResourceName() : null;
  const $ = (selector) => document.querySelector(selector);
  const escape = (v) => String(v ?? '').replace(/[&<>"']/g, x => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[x]);
  const glyphs = {
    dashboard:'<rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/>',
    garage:'<path d="M3 21V9l9-6 9 6v12"/><path d="M7 21v-9h10v9M7 16h10M10 12v9"/>',
    car:'<path d="M5 17h14l2-6-2-5H5l-2 5 2 6ZM5 17v3M19 17v3M3 11h18M7 14h.01M17 14h.01"/>',
    plus:'<path d="M12 5v14M5 12h14"/>',
    arrow:'<path d="M5 12h14M13 6l6 6-6 6"/>',
    back:'<path d="m15 18-6-6 6-6"/>',
    refresh:'<path d="M20 11a8 8 0 0 0-14-5L4 8m0-4v4h4M4 13a8 8 0 0 0 14 5l2-2m0 4v-4h-4"/>',
    close:'<path d="M18 6 6 18M6 6l12 12"/>',
    search:'<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
    check:'<path d="m5 12 4 4L19 6"/>',
    alert:'<circle cx="12" cy="12" r="10"/><path d="M12 7v6M12 17h.01"/>',
    pin:'<path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/>',
    edit:'<path d="m16 4 4 4-12 12H4v-4L16 4ZM14 6l4 4"/>',
    key:'<circle cx="8" cy="15" r="4"/><path d="m11 12 9-9 2 2-3 3 2 2-3 3-2-2-3 3"/>',
    users:'<circle cx="9" cy="8" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M16 5a3 3 0 0 1 0 6m2 5a5 5 0 0 1 3 4"/>',
    shield:'<path d="M12 22S4 18 4 11V5l8-3 8 3v6c0 7-8 11-8 11Z"/><path d="m9 12 2 2 4-4"/>',
    trash:'<path d="M3 6h18M8 6V4h8v2m3 0-1 15H6L5 6m5 4v7m4-7v7"/>',
    filter:'<path d="M4 6h16M7 12h10M10 18h4"/>',
    return:'<path d="m9 14-4-4 4-4M5 10h10a5 5 0 0 1 0 10h-3"/>',
    truck:'<path d="M3 6h12v11H3zM15 10h4l2 3v4h-6M7 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4ZM17 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z"/>',
    settings:'<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.2.2-2.8 2.8-.2-.2a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V22h-4v-1.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.9.3l-.2.2-2.8-2.8.2-.2a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H2v-4h1.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.9l-.2-.2 2.8-2.8.2.2a1.7 1.7 0 0 0 1.9.3 1.7 1.7 0 0 0 1-1.5V2h4v1.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.2-.2 2.8 2.8-.2.2a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.5 1H22v4h-1.1a1.7 1.7 0 0 0-1.5 1Z"/>',
    upload:'<path d="M12 16V3m0 0L7 8m5-5 5 5M4 17v4h16v-4"/>',
    info:'<circle cx="12" cy="12" r="10"/><path d="M12 10v6M12 7h.01"/>',
    map:'<path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6ZM9 3v15M15 6v15"/>'
  };
  const icon = (name, size=18) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyphs[name] || glyphs.info}</svg>`;
  const state = { visible:false, loading:false, data:{garages:[],playerJob:'—',grade:0,isAdmin:false,canCreate:false,playerLabel:'Employé'}, view:'overview', selectedId:null, tab:'fleet', search:'', statusFilter:'all', categoryFilter:'all', modal:null, pendingSelectedId:null };
  let busy = false;
  let uiEpoch = 0, activeSession = null, reloadSequence = 0, lastRenderedModal = null;
  const controllers = new Set();
  const blankData = () => ({garages:[],playerJob:'—',grade:0,isAdmin:false,canCreate:false,playerLabel:'Employé'});
  const list = value => Array.isArray(value) ? value.filter(x => x && typeof x === 'object') : [];
  const flag = value => value === true || value === 1 || value === '1';
  const searchText = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('fr');
  function normalizeData(payload) {
    const data = payload && typeof payload === 'object' ? payload : {};
    return {...blankData(), ...data, playerLabel:String(data.playerLabel || 'Employé'), playerJob:String(data.playerJob || '—'),
      isAdmin:flag(data.isAdmin), canCreate:flag(data.canCreate), singleGarage:flag(data.singleGarage),
      garages:list(data.garages).filter(g => Number.isSafeInteger(Number(g.id)) && Number(g.id) > 0).map(g => ({...g,
        id:Number(g.id),name:String(g.name || 'Garage'),job:String(g.job || '—'),
        abilities:Object.fromEntries(Object.entries(g.abilities || {}).map(([key,value]) => [key,flag(value)])),
        permissions:{...defaultPermissions(),...(g.permissions || {}),access_rules:normalizedRule(g.permissions?.access_rules)},
        categories:list(g.categories).filter(c => Number.isSafeInteger(Number(c.id)) && Number(c.id) > 0).map(c => ({...c,id:Number(c.id),name:String(c.name || 'Catégorie'),access_rules:normalizedRule(c.access_rules)})),
        vehicles:list(g.vehicles).filter(v => Number.isSafeInteger(Number(v.id)) && Number(v.id) > 0).map(v => ({...v,id:Number(v.id),label:String(v.label || v.model || 'Véhicule'),model:String(v.model || ''),stored:flag(v.stored),canWithdraw:flag(v.canWithdraw),canStore:flag(v.canStore)})),
        spawnPoints:list(g.spawnPoints).filter(p => Number.isSafeInteger(Number(p.id)) && Number(p.id) > 0).map(p => ({...p,id:Number(p.id)})),
        storePoints:list(g.storePoints).filter(p => Number.isSafeInteger(Number(p.id)) && Number(p.id) > 0).map(p => ({...p,id:Number(p.id)}))
      }))};
  }
  function invalidateSession(session = activeSession) {
    uiEpoch++; reloadSequence++; activeSession = session;
    controllers.forEach(controller => controller.abort()); controllers.clear();
    busy = false; state.loading = false; setBusy(false);
  }
  function setBusy(value) {
    busy = value;
    $('#app').setAttribute('aria-busy', String(value || state.loading));
    document.querySelectorAll('[data-action]').forEach(button => {
      if (value) {if (!('wasDisabled' in button.dataset)) button.dataset.wasDisabled = String(button.disabled);button.disabled = true;}
      else if ('wasDisabled' in button.dataset) {button.disabled = button.dataset.wasDisabled === 'true';delete button.dataset.wasDisabled;}
    });
    $('#refresh-button').disabled = value || state.loading;
    const status = $('#operation-status');
    if (status) {status.textContent = value ? 'Opération en cours…' : state.loading ? 'Actualisation…' : '';status.classList.toggle('hidden', !value && !state.loading);}
  }
  function showError(message) {
    toast(message || 'Opération refusée. Réessayez après actualisation.', true);
    if (state.modal) {state.modal.error = message;renderModal();}
  }
  function decorateControls() {
    document.querySelectorAll('button[title]').forEach(button => {if (!button.hasAttribute('aria-label')) button.setAttribute('aria-label', button.title);});
    document.querySelectorAll('.nav-item').forEach(button => {button.setAttribute('aria-label', button.textContent.trim());if (button.classList.contains('active')) button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');});
    document.querySelectorAll('[data-action^="tab-"]').forEach(button => {button.setAttribute('role','tab');button.setAttribute('aria-selected',String(button.dataset.action==='tab-'+state.tab));button.setAttribute('aria-controls','content');button.parentElement?.setAttribute('role','tablist');});
    document.querySelectorAll('.field').forEach((field, index) => {
      const label = field.querySelector('label'), control = field.querySelector('input, select, textarea');
      if (label && control) {if (!control.id) control.id = 'control-' + index;label.htmlFor = control.id;}
    });
    const names = {'fleet-search':'Rechercher un véhicule, une plaque ou une catégorie','fleet-category':'Filtrer par catégorie','fleet-filter':'Filtrer par statut'};
    Object.entries(names).forEach(([id,label]) => {const control = $('#' + id);if (control) control.setAttribute('aria-label',label);});
    document.querySelectorAll('[data-search-acl]').forEach(control => control.setAttribute('aria-label','Rechercher un employé'));
  }

  const garage = () => state.data.garages.find(g => Number(g.id) === Number(state.selectedId));
  const setTab = (tab) => { state.tab=tab; state.search='';state.statusFilter='all';state.categoryFilter='all';render(); };
  const vehicleCounts = (items) => ({ total:items.length, stored:items.filter(v=>v.stored).length, out:items.filter(v=>!v.stored).length });
  const totalCounts = () => vehicleCounts(state.data.garages.flatMap(g=>g.vehicles || []));
  const formatCoords = (p) => p && Number.isFinite(Number(p.x)) ? `${Number(p.x).toFixed(2)} / ${Number(p.y).toFixed(2)} / ${Number(p.z).toFixed(2)} · ${Number(p.h||0).toFixed(0)}°` : 'Non configuré';
  const e = escape;

  async function request(name, data={}) {
    if (!IS_FIVEM && window.EnterpriseGaragePreview) return window.EnterpriseGaragePreview.request(name, data);
    if (!IS_FIVEM) return {ok:false,error:'Cette interface doit être ouverte depuis FiveM.'};
    const epoch = uiEpoch, controller = new AbortController();
    controllers.add(controller);
    const timer = setTimeout(() => controller.abort(), name === 'selectPosition' ? 130000 : 20000);
    try {
      const response = await fetch(`https://${resource}/${name}`, {method:'POST',headers:{'Content-Type':'application/json; charset=UTF-8'},body:JSON.stringify({...data,uiSession:activeSession}),signal:controller.signal});
      if (epoch !== uiEpoch) return {ok:false,stale:true};
      if (!response.ok) return {ok:false,error:'Le service du garage ne répond pas correctement. Actualisez puis réessayez.'};
      const result = await response.json();
      if (epoch !== uiEpoch) return {ok:false,stale:true};
      return result && typeof result === 'object' && typeof result.ok === 'boolean' ? result : {ok:false,error:'Réponse du garage invalide. Actualisez puis réessayez.'};
    } catch (error) {
      if (epoch !== uiEpoch) return {ok:false,stale:true};
      return {ok:false,error:controller.signal.aborted ? 'Le garage met trop de temps à répondre. Actualisez avant de réessayer.' : 'Connexion avec le garage interrompue. Actualisez puis réessayez.'};
    } finally {clearTimeout(timer);controllers.delete(controller);}
  }
  const toast = (msg,error=false) => {
    const node=document.createElement('div');node.className=`toast ${error?'error':''}`;
    node.innerHTML=icon(error?'alert':'check')+`<span>${e(msg)}</span>`;
    const area=$('#toast-area');while(area.children.length>=3)area.firstElementChild.remove();node.setAttribute('role',error?'alert':'status');area.appendChild(node);setTimeout(()=>node.remove(),6000);
  };

  function renderNav() {
    const {garages,playerJob,playerLabel,grade,isAdmin} = state.data;
    $('#nav-primary').innerHTML=`${!state.data.singleGarage?`<button type="button" class="nav-item ${state.view==='overview'?'active':''}" data-action="overview">${icon('dashboard')}<span>Vue d’ensemble</span></button>`:''}
      <button type="button" class="nav-item ${state.view==='garage'?'active':''}" data-action="select-first">${icon('truck')}<span>Flotte automobile</span><span class="nav-count">${totalCounts().total}</span></button>`;
    $('#nav-garages').innerHTML=garages.length ? garages.map(g=>`<button type="button" class="nav-item ${state.view==='garage' && +state.selectedId===+g.id?'active':''}" data-action="garage" data-id="${g.id}">${icon('garage')}<span>${e(g.name)}</span></button>`).join('') : `<div style="color:#74849b;font-size:11px;padding:0 14px;line-height:1.6">Aucun garage disponible</div>`;
    $('#profile-name').textContent=playerLabel;$('#profile-job').textContent=`${playerJob} · grade ${grade}`;
    $('#avatar').textContent=playerLabel.split(/\s+/).map(a=>a[0]||'').slice(0,2).join('').toUpperCase();
    $('#role-chip').textContent=isAdmin?'ADMINISTRATEUR':'ENTREPRISE';
    $('#breadcrumb-current').textContent=state.view==='overview'?'Tableau de bord':garage()?.name || 'Garage';
  }
  const kpi = (name,value,hint,glyph) => `<article class="kpi-card"><div class="kpi-title">${icon(glyph)}${e(name)}</div><div class="kpi-number">${value}</div><div class="kpi-desc">${e(hint)}</div></article>`;
  const empty = (heading,desc,glyph='garage')=>`<div class="empty-state">${icon(glyph,30)}<strong>${e(heading)}</strong><p>${e(desc)}</p></div>`;
  const garageCard=(g)=>{const n=vehicleCounts(g.vehicles||[]);return `<article class="garage-card"><div class="garage-card-top"><span class="garage-symbol">${icon('garage')}</span><span class="mini-tag">${e(g.job)}</span></div><h3>${e(g.name)}</h3><p>Flotte de véhicules de l’entreprise</p><div class="garage-card-footer"><span><strong>${n.total}</strong> véhicules · <strong>${n.stored}</strong> disponibles</span><button type="button" class="mini-link" data-action="garage" data-id="${g.id}">GÉRER ${icon('arrow')}</button></div></article>`;};

  function renderOverview(){
    const counts=totalCounts();const garages=state.data.garages;
    $('#content').innerHTML=`<div class="heading-row"><div><h1>Vue d’ensemble</h1><p class="subtitle">Vos garages et véhicules de service, réunis dans un espace de gestion.</p></div>${state.data.canCreate?`<button class="button primary" data-action="new-garage">${icon('plus')} Nouveau garage</button>`:''}</div>
      <div class="kpi-grid">${kpi('Garages actifs',garages.length,'Garages accessibles','garage')}${kpi('Véhicules de flotte',counts.total,'Véhicules enregistrés','car')}${kpi('Disponibles',counts.stored,`${counts.out} actuellement en circulation`,'check')}</div>
      <div class="section-heading"><h2>Vos implantations</h2><span class="section-hint">${garages.length} garage${garages.length>1?'s':''} enregistré${garages.length>1?'s':''}</span></div>
      ${garages.length?`<div class="garage-grid">${garages.map(garageCard).join('')}</div>`:empty('Aucun garage accessible','Créez votre premier garage ou demandez à votre responsable de vous accorder les permissions.')}
      <div class="notice-card"><div class="notice-icon">${icon('key')}</div><div><strong>Clés partagées automatiquement</strong><p>Les clés des véhicules sortis sont attribuées exclusivement aux grades et employés autorisés pour le garage et la catégorie. Elles sont révoquées après chaque changement d’accès.</p></div></div>`;
  }

  const catName=(g,v)=>g.categories?.find(c=>Number(c.id)===Number(v.category_id))?.name || 'Sans catégorie';
  const categorySelect=(g,selected=0)=>`<select class="input" name="categoryId"><option value="0" ${!selected?'selected':''}>Sans catégorie</option>${(g.categories||[]).map(c=>`<option value="${c.id}" ${Number(c.id)===Number(selected)?'selected':''}>${e(c.name)}</option>`).join('')}</select>`;
  function vehicleRow(g,v){
    const buttons=[];
    if(v.stored && v.canWithdraw) buttons.push(`<button class="row-button" data-action="withdraw" data-vehicle="${v.id}" title="Choisir un point de sortie">${icon('arrow',13)} Sortir</button>`);
    if(!v.stored && v.canStore) buttons.push(`<button class="row-button secondary" data-action="store" data-vehicle="${v.id}" title="Ranger ce véhicule en étant à son volant">Ranger</button>`);
    if(!v.stored && g.abilities.manage) buttons.push(`<button class="row-button secondary" data-action="recover" data-vehicle="${v.id}" title="Récupérer un véhicule disparu">${icon('return',13)}</button>`);
    if(g.abilities.rename) buttons.push(`<button class="row-button secondary" data-action="rename-vehicle" data-vehicle="${v.id}" title="Renommer le véhicule">${icon('edit',13)}</button>`);
    if(g.abilities.assign_category) buttons.push(`<button class="row-button secondary" data-action="classify-vehicle" data-vehicle="${v.id}" title="Changer de catégorie">${icon('filter',13)}</button>`);
    if(v.stored && g.abilities.fleet_remove) buttons.push(`<button class="row-button danger" data-action="remove-vehicle" data-vehicle="${v.id}" title="Retirer de la flotte">${icon('trash',13)}</button>`);
    return `<tr><td><div class="car-cell"><div class="car-icon">${icon(v.vehicle_type==='bike'?'truck':'car')}</div><div><strong>${e(v.label)}</strong><span>${e(v.model)}</span></div></div></td><td><span class="plate">${e(v.plate)}</span></td><td><span class="category-chip">${icon('filter',13)} ${e(catName(g,v))}</span></td><td><span class="status ${v.stored?'stored':'out'}">${v.stored?'Au garage':'En circulation'}</span></td><td><div class="row-actions">${buttons.join('')||'<span class="faded">—</span>'}</div></td></tr>`;
  }

  function renderFleet(g) {
    const n=vehicleCounts(g.vehicles||[]), q=searchText(state.search.trim());
    const bridgeNotice=state.data.bridge?.enabled
      ? `Les véhicules de société${state.data.bridge.allowEmployeeOwned?' et vos véhicules personnels autorisés':''} peuvent être transférés depuis okokGarage. Ils rejoignent la flotte partagée ; leur propriétaire est conservé et le retrait les rend à leur garage d’origine.`
      : 'Seuls les véhicules enregistrés au nom de l’entreprise peuvent être importés. Le retrait de la flotte ne supprime pas le véhicule possédé.';
    const vehicles=(g.vehicles||[]).filter(v=>searchText(`${v.label} ${v.plate} ${v.model} ${catName(g,v)}`).includes(q)
      && (state.statusFilter==='all'||(state.statusFilter==='stored'?v.stored:!v.stored))
      && (state.categoryFilter==='all'||String(v.category_id||0)===state.categoryFilter));
    $('#content').innerHTML=`<div class="heading-row"><div><h1>${e(g.name)}</h1><p class="subtitle">Inventaire, catégories, sorties multiples et disponibilité en temps réel.</p></div>
      <div class="toolbar-actions">${g.abilities.store?`<button class="button" data-action="store">${icon('return')} Ranger mon véhicule</button>`:''}${g.abilities.fleet_add?`<button class="button primary" data-action="register">${icon('plus')} Importer un véhicule possédé</button>`:''}</div></div>
      <div class="kpi-grid">${kpi('Véhicules',n.total,'Effectif de la flotte','car')}${kpi('Au garage',n.stored,'Prêts à être sortis','check')}${kpi('En circulation',n.out,'Actuellement à l’extérieur','arrow')}</div>
      <div class="section-heading"><h2>Inventaire automobile</h2><span class="section-hint">${(g.categories||[]).length} catégories · ${g.spawnPoints?.length||0} sorties</span></div>
      <div class="toolbar"><div class="search-wrap">${icon('search')}<input class="search-input" id="fleet-search" type="search" value="${e(state.search)}" placeholder="Véhicule, plaque ou catégorie…" maxlength="60"></div>
      <div class="toolbar-actions"><select class="filter-control" id="fleet-category"><option value="all">Toutes les catégories</option><option value="0" ${state.categoryFilter==='0'?'selected':''}>Sans catégorie</option>${(g.categories||[]).map(c=>`<option value="${c.id}" ${state.categoryFilter===String(c.id)?'selected':''}>${e(c.name)}</option>`).join('')}</select><select class="filter-control" id="fleet-filter"><option value="all" ${state.statusFilter==='all'?'selected':''}>Tous les statuts</option><option value="stored" ${state.statusFilter==='stored'?'selected':''}>Au garage</option><option value="out" ${state.statusFilter==='out'?'selected':''}>En circulation</option></select></div></div>
      <p class="filter-summary" role="status">${vehicles.length} véhicule${vehicles.length>1?'s':''} affiché${vehicles.length>1?'s':''} sur ${n.total}${q || state.statusFilter!=='all' || state.categoryFilter!=='all'?' · filtres actifs <button type="button" class="mini-link" data-action="clear-filters">Effacer les filtres</button>':''}</p><div class="fleet-panel">${vehicles.length?`<div class="table-scroll"><table><thead><tr><th>Véhicule</th><th>Immatriculation</th><th>Catégorie</th><th>État</th><th style="text-align:right">Actions</th></tr></thead><tbody>${vehicles.map(v=>vehicleRow(g,v)).join('')}</tbody></table></div>`:empty(n.total?'Aucun résultat pour ces filtres':'La flotte est vide',n.total?'Effacez les filtres pour retrouver l’inventaire complet.':g.abilities.fleet_add?'Importez un véhicule de société pour constituer la flotte.':'Votre responsable peut ajouter des véhicules à cette flotte.','search')}
      <div class="fleet-footnote">${icon('info')} ${e(bridgeNotice)}</div></div>
      <div class="notice-card"><div class="notice-icon">${icon('key')}</div><div><strong>Clés partagées par entreprise</strong><p>Chaque véhicule sorti n’accorde ses clés qu’aux employés autorisés par les droits d’accès du garage ET de sa catégorie. Les permissions sont revérifiées côté serveur.</p></div></div>`;
  }

  function renderSettings(g) {
    const points=(kind)=>{const list=kind==='store'?g.storePoints:g.spawnPoints;return `<div class="point-list">${(list||[]).map(p=>`<div class="point-row"><div class="point-symbol">${icon(kind==='store'?'return':'map')}</div><div class="point-summary"><strong>${e(p.label)}</strong><span>${e(formatCoords(p.coords))}</span></div>${g.abilities.structure&&list.length>1?`<button class="row-button danger" data-action="remove-point" data-point="${p.id}" data-kind="${kind}" title="Supprimer ce point">${icon('trash',14)}</button>`:''}</div>`).join('')}</div>${g.abilities.structure?`<button class="button sm" data-action="add-point" data-kind="${kind}">${icon('plus',15)} Ajouter un point de ${kind==='store'?'rangement':'sortie'}</button>`:''}`;};
    $('#content').innerHTML=`<div class="heading-row"><div><h1>Paramètres du garage</h1><p class="subtitle">Emplacements réservés au staff serveur · Accès et clés gérés par l'entreprise.</p></div><div class="toolbar-actions">${g.abilities.manage?`<button class="button" data-action="edit-permissions">${icon('shield')} Permissions & clés</button>`:''}${g.abilities.structure?`<button class="button primary" data-action="edit-garage">${icon('edit')} Configuration staff</button>`:''}</div></div>
      <div class="settings-stack"><div class="setting-card"><h2>Informations générales</h2><p>Identité et rattachement du garage à votre entreprise.</p><div class="setting-row"><div><strong>Nom du garage</strong><span>Affiché dans l'interface et au point d'accès</span></div><span class="tag-right">${e(g.name)}</span></div><div class="setting-row"><div><strong>Métier associé</strong><span>Clés Wasabi réservées aux grades et employés autorisés de ce métier</span></div><span class="tag-right">${e(g.job)}</span></div><div class="setting-row"><div><strong>Point d'accès unique</strong><span>${e(formatCoords(g.entrance))}</span></div>${icon('pin')}</div><div class="setting-row"><div><strong>Ouverture</strong><span>${g.interaction?.mode==='ped'?'Ped ox_target dédié au garage':'Marqueur E dédié au garage'}</span></div><span class="tag-right">${g.interaction?.mode==='ped'?e(g.interaction?.pedModel||'Ped'):'Marqueur'}</span></div><div class="hint-box">${icon('shield')} Nom, rattachement métier, ped et coordonnées modifiables uniquement par le staff serveur. Chaque accès ouvre exclusivement ce garage.</div></div>
      <div class="setting-card"><div class="section-heading"><h2>Zones de rangement</h2><span class="section-hint">${g.storePoints?.length||0} point(s)</span></div><p>Les employés peuvent ranger un véhicule à proximité de n’importe quel point défini ci-dessous.</p>${points('store')}</div>
      <div class="setting-card"><div class="section-heading"><h2>Points de sortie</h2><span class="section-hint">${g.spawnPoints?.length||0} point(s)</span></div><p>Au moment de sortir un véhicule, choisir une sortie ou laisser le serveur utiliser le premier emplacement libre.</p>${points('spawn')}</div>
      <div class="setting-card"><h2>Permissions du garage</h2><p>Accès par grade minimum ou sélection de grades précis et de personnes. Les catégories peuvent ajouter leurs propres restrictions.</p>${[['access','Accès à l’interface'],['withdraw','Sortir un véhicule'],['store','Ranger un véhicule'],['manage','Administrer les permissions et récupérer les véhicules'],['fleet_add','Importer un véhicule possédé'],['fleet_remove','Retirer un véhicule de la flotte'],['categories','Créer / modifier des catégories'],['assign_category','Classer un véhicule'],['rename','Renommer le label visible']].map(([key,label])=>`<div class="setting-row"><div><strong>${label}</strong><span>Emploi ${e(g.job)} uniquement</span></div><span class="tag-right">${key==='access' && g.permissions.access_rules?.mode==='list'?e(accessSummary(g.permissions.access_rules)): 'Grade '+Number(g.permissions[key]??0)}</span></div>`).join('')}</div>
      ${g.abilities.structure?`<div class="setting-card"><h2>Zone sensible · Staff serveur</h2><p>La suppression efface le garage et sa flotte, à condition que tous les véhicules soient rangés.</p><button class="button danger" data-action="delete-garage">${icon('trash')} Supprimer le garage</button></div>`:''}</div>`;
  }

  function renderCategories(g){
    const categories=g.categories||[];
    $('#content').innerHTML=`<div class="heading-row"><div><h1>Catégories de véhicules</h1><p class="subtitle">Définissez les véhicules, les grades précis et les employés ayant accès à chaque catégorie.</p></div>${g.abilities.categories?`<button class="button primary" data-action="new-category">${icon('plus')} Nouvelle catégorie</button>`:''}</div>
    <div class="category-grid">${categories.length?categories.map(c=>`<article class="category-card"><div class="category-card-head"><span class="category-icon">${icon('filter')}</span><span class="category-total">${g.vehicles.filter(v=>Number(v.category_id)===Number(c.id)).length} véhicules</span></div><h3>${e(c.name)}</h3><div class="grade-tags"><span>${c.access_rules?.mode==='list'?e(accessSummary(c.access_rules)):`Voir · G${c.access_grade}`}</span><span>Sortir · G${c.withdraw_grade}</span><span>Ranger · G${c.store_grade}</span></div>${g.abilities.categories?`<div class="category-actions"><button class="button sm" data-action="edit-category" data-category="${c.id}">${icon('edit',14)} Modifier</button><button class="button sm danger" data-action="delete-category" data-category="${c.id}">${icon('trash',14)}</button></div>`:''}</article>`).join(''):empty('Aucune catégorie','Créez vos catégories pour organiser les véhicules de cette entreprise.','filter')}</div>
    <div class="notice-card"><div class="notice-icon">${icon('shield')}</div><div><strong>Autorisations cumulatives</strong><p>Les listes d’accès peuvent combiner plusieurs grades exacts et personnes choisies. Les employés doivent être autorisés dans le garage ET la catégorie pour recevoir les clés Wasabi.</p></div></div>`;
  }

  function renderGarage() {
    const g=garage();if(!g){state.view='overview';renderOverview();return;}
    $('#content').innerHTML=`<div class="toolbar-actions" style="margin-bottom:18px"><button class="button sm ${state.tab==='fleet'?'primary':''}" data-action="tab-fleet">${icon('car')} Flotte</button><button class="button sm ${state.tab==='categories'?'primary':''}" data-action="tab-categories">${icon('filter')} Catégories</button><button class="button sm ${state.tab==='settings'?'primary':''}" data-action="tab-settings">${icon('settings')} Paramètres</button></div><div id="subview"></div>`;
    const content=$('#content');const menu=content.firstElementChild;const subview=content.querySelector('#subview');
    if(state.tab==='settings') renderSettings(g); else if(state.tab==='categories')renderCategories(g); else renderFleet(g);
    content.prepend(menu);
    decorateControls();setBusy(busy);
  }

  function render(){
    if(!state.visible)return;
    renderNav();
    if (state.loading && !state.data.garages.length) $('#content').innerHTML=empty('Chargement des garages…','Récupération de votre flotte et de vos autorisations.','refresh');
    else if (state.loadError && !state.data.garages.length) $('#content').innerHTML=empty('Impossible de charger les garages',state.loadError,'alert')+'<button class="button primary retry-button" data-action="reload">Réessayer</button>';
    else if(state.view==='garage')renderGarage();else renderOverview();
    renderModal();decorateControls();setBusy(busy);
  }
  function openSelect(id){state.selectedId=Number(id);state.view='garage';state.tab='fleet';state.search='';state.statusFilter='all';state.categoryFilter='all';render();$('#scroll-content').scrollTop=0;}
  async function reload(silent=false) {
    const sequence=++reloadSequence, epoch=uiEpoch;
    state.loading=true;state.loadError='';render();
    const response=await request('fetchData');
    if (sequence!==reloadSequence || epoch!==uiEpoch || response.stale) return false;
    state.loading=false;
    if(!response.ok){state.loadError=response.error||'Actualisez pour réessayer.';toast(state.loadError,true);render();return false;}
    state.data=normalizeData(response);
    if(state.selectedId && !garage())state.selectedId=null;
    if(!state.selectedId && state.data.garages.length)state.selectedId=state.data.garages[0].id;
    render();return true;
  }
  async function mutate(task,done) {
    if(busy)return;
    const epoch=uiEpoch, modal=state.modal;
    setBusy(true);
    try {
      const response=await task();
      if(epoch!==uiEpoch || response.stale)return;
      if(!response.ok){showError(response.error);return;}
      toast(response.message||'Opération effectuée.');
      if(state.modal===modal)state.modal=null;
      renderModal();
      await reload(true);
      if(epoch===uiEpoch && done)done(response);
    } finally {if(epoch===uiEpoch)setBusy(false);}
  }
  async function perform(action,data,done){return mutate(()=>request('execute',{action,data}),done);}

  const defaultRule=()=>({mode:'all',grades:[],identifiers:[]});
  const defaultPermissions=()=>({access:0,withdraw:0,store:0,manage:4,fleet_add:3,fleet_remove:4,categories:4,assign_category:3,rename:3,access_rules:defaultRule()});
  const normalizedRule=(rule)=>({mode:rule?.mode==='list'?'list':'all',grades:Array.isArray(rule?.grades)?rule.grades.map(Number).filter(Number.isFinite):[],identifiers:Array.isArray(rule?.identifiers)?rule.identifiers.filter(x=>typeof x==='string'):[]});
  const accessSummary=(rule)=>rule?.mode==='list'?`${(rule.grades||[]).length} grade(s) · ${(rule.identifiers||[]).length} employé(s)`:'Grade minimum';
  function readRule(field,current){
    const selector=`[data-acl="${field}"]`;
    const mode=document.querySelector(`${selector} .acl-mode`)?.value || current?.mode || 'all';
    if(mode!=='list')return defaultRule();
    const grades=Array.from(document.querySelectorAll(`${selector} [data-role="grade"]:checked`)).map(x=>Number(x.value));
    const identifiers=Array.from(document.querySelectorAll(`${selector} [data-role="employee"]:checked`)).map(x=>x.value);
    return {mode:'list',grades,identifiers};
  }
  async function loadRoster(modal){
    const job=modal.type==='category'?garage()?.job:modal.values?.job;
    if(!job)return toast('Indiquez d’abord le nom du métier.',true);
    if(modal.rosterLoading)return;
    modal.rosterLoading=true;renderModal();
    const response=await request('execute',{action:'listEmployees',data:modal.type==='category'?{garageId:garage().id}:{garageId:modal.type==='edit'||modal.type==='permissions'?modal.values.id:null,job}});
    if(state.modal!==modal || response.stale)return;
    modal.rosterLoading=false;
    if(!response.ok){modal.roster=null;toast(response.error||'Lecture des employés impossible',true);}
    else modal.roster={employees:list(response.employees),grades:list(response.grades),job:String(response.job||job)};
    renderModal();
  }
  function accessEditor(name,rule,roster,title){
    const selected=normalizedRule(rule),enabled=selected.mode==='list';
    const loaded=roster&&roster.job===(state.modal?.type==='category'?garage()?.job:state.modal?.values?.job);
    const grades=loaded?roster.grades:[],staff=loaded?roster.employees:[];
    const selectedGrades=new Set(selected.grades),selectedUsers=new Set(selected.identifiers);
    const unknown=selected.identifiers.filter(id=>!staff.some(x=>x.identifier===id));
    return `<section class="acl-editor" data-acl="${e(name)}"><div class="acl-header"><div><strong>${e(title)}</strong><span>Les clés suivent également ces autorisations.</span></div>${icon('shield')}</div>
      <div class="field"><label>Mode d'accès</label><select class="input acl-mode" data-rule="${e(name)}"><option value="all" ${!enabled?'selected':''}>Classique : grade minimum</option><option value="list" ${enabled?'selected':''}>Liste : grades exacts et/ou personnes</option></select></div>
      ${enabled?`<div class="acl-hint">Accès accordé si le grade correspond à l’un des grades cochés <strong>OU</strong> si l’employé est sélectionné individuellement. Les autres employés n’ont pas les clés.</div>
        <div class="acl-roster-heading"><strong>Grades précis</strong><button type="button" class="button sm" data-action="load-staff">${icon('refresh',14)} ${state.modal?.rosterLoading?'Chargement…':'Actualiser le personnel'}</button></div>
        ${loaded?`<div class="acl-checkbox-grid">${grades.length?grades.map(g=>`<label class="acl-option"><input type="checkbox" data-role="grade" value="${Number(g.grade)}" ${selectedGrades.has(Number(g.grade))?'checked':''}><span><b>Grade ${Number(g.grade)}</b><small>${e(g.label||g.name||'')}</small></span></label>`).join(''):'<span class="acl-empty">Aucun grade connu dans job_grades.</span>'}</div>
          <div class="acl-roster-heading"><strong>Employés de l'entreprise</strong><span>${staff.length} disponible(s)</span></div>
          <input type="search" class="input acl-search" data-search-acl="${e(name)}" placeholder="Rechercher un employé…" autocomplete="off">
          <div class="acl-checkbox-grid acl-employees">${staff.map(person=>`<label class="acl-option" data-person-search="${e((person.name+' '+person.identifier).toLowerCase())}"><input type="checkbox" data-role="employee" value="${e(person.identifier)}" ${selectedUsers.has(person.identifier)?'checked':''}><span><b>${e(person.name)}</b><small>${person.online?'● En ligne · ':''}${e(person.identifier)}</small></span></label>`).join('')}${unknown.map(id=>`<label class="acl-option acl-unknown"><input type="checkbox" data-role="employee" value="${e(id)}" checked><span><b>Ancien membre / introuvable</b><small>${e(id)} · décochez pour retirer</small></span></label>`).join('')}</div>`
          :`<div class="acl-empty">${state.modal?.rosterLoading?'Chargement du personnel…':'Charge la liste du métier pour choisir plusieurs grades et employés.'}</div><button type="button" class="button sm" data-action="load-staff">${icon('users',14)} Charger grades et employés</button>`}
        <p class="form-help">L’appartenance au métier est vérifiée à l’enregistrement et à chaque attribution de clé. Les employés hors entreprise ne peuvent pas être ajoutés.</p>`:''}</section>`;
  }

  const deepCopy=(x)=>JSON.parse(JSON.stringify(x));
  function openModal(type,payload={}){state.modal={type,...payload,returnFocus:document.activeElement};renderModal();}
  function coordsRow(key,title,value){return `<div class="position-field"><div><strong>${e(title)}</strong><span>${e(formatCoords(value))}</span></div><button type="button" class="button sm" data-action="capture" data-field="${e(key)}">${icon('pin')} Capturer</button></div>`;}
  const field=(name,label,value='',type='text',extra='')=>`<div class="field"><label for="f-${name}">${e(label)}</label><input class="input" id="f-${name}" name="${name}" type="${type}" value="${e(value)}" ${extra}></div>`;
  function permissionsFields(values){return `<div class="form-divider"></div><h3 class="form-title">Permissions des actions par grade ESX</h3><div class="field-grid">${[['access','Grade minimum de base pour accès'],['withdraw','Sortie'],['store','Rangement'],['manage','Gestion des permissions entreprise'],['fleet_add','Importer les véhicules'],['fleet_remove','Retirer de la flotte'],['categories','Gérer les catégories'],['assign_category','Classer les véhicules'],['rename','Renommer les labels']].map(([key,label])=>field(`p_${key}`,label,values.permissions[key],'number','min="0" max="99" step="1" required')).join('')}</div><p class="form-help">En mode « liste », les grades choisis remplacent le seuil d’accès. Les seuils de sortie, rangement et de gestion restent applicables.</p>${accessEditor('garage',values.permissions.access_rules,state.modal.roster,'Qui peut accéder au garage et recevoir ses clés ?')}`;}
  function modalMarkup() {
    const m=state.modal;if(!m)return '';
    const g=garage(),edit=m.type==='edit';
    const header=(title,desc)=>`<div class="modal-header"><div><h2>${e(title)}</h2><p>${e(desc)}</p></div><button type="button" class="icon-button" aria-label="Fermer la fenêtre" data-action="modal-close">${icon('close')}</button></div>`;
    const footer=(action,label,danger=false)=>`<div class="modal-footer"><button type="button" class="button" data-action="modal-close">Annuler</button><button type="button" class="button ${danger?'danger':'primary'}" data-action="${action}">${icon(danger?'trash':'check')} ${e(label)}</button></div>`;
    if(m.type==='create'||edit){const v=m.values;
      return `${header(edit?'Modifier le garage':'Créer un garage entreprise','Gestion des positions et permissions intégralement en jeu.')}
      <div class="modal-scroll"><form id="garage-form"><div class="field-grid">${field('name','Nom du garage',v.name,'text','maxlength="60" required')}${field('job','Métier ESX',v.job,'text',`${edit&&!state.data.isAdmin?'readonly':''} maxlength="60" required`)}</div>
      <div class="form-divider"></div><h3 class="form-title">Point d'accès unique${edit?'':' et première sortie'}</h3><div style="display:grid;gap:10px">${coordsRow('entrance','Point d’accès à l’interface',v.entrance)}${!edit?coordsRow('spawn','Première sortie du véhicule',v.spawn):''}</div><p class="form-help">Un emplacement d'accès appartient à un seul garage. Une entreprise peut avoir plusieurs garages, chacun avec sa propre entrée. Les positions et le ped sont réservés au staff.</p><div class="form-divider"></div><h3 class="form-title">Ouverture du garage · staff uniquement</h3><div class="field-grid"><div class="field"><label>Type d'interaction</label><select class="input" name="interactionMode"><option value="marker" ${v.interaction?.mode!=='ped'?'selected':''}>Marqueur (touche E)</option><option value="ped" ${v.interaction?.mode==='ped'?'selected':''}>Ped avec ox_target</option></select></div><div class="field"><label>Modèle du ped</label><select class="input" name="pedModel">${['s_m_m_security_01','s_m_m_dockwork_01','s_m_y_cop_01','s_f_y_cop_01','s_m_m_autoshop_01','a_m_m_business_01'].map(model=>`<option value="${model}" ${v.interaction?.pedModel===model?'selected':''}>${model}</option>`).join('')}</select></div><div class="field full">${field('scenario','Animation du ped',v.interaction?.scenario||'WORLD_HUMAN_CLIPBOARD','text','maxlength="64" required')}</div></div>
      ${permissionsFields(v)}</form></div>${footer('save-garage',edit?'Enregistrer':'Créer le garage')}`;
    }
    if(m.type==='permissions'){return `${header('Permissions & clés','Réservé aux responsables autorisés de l’entreprise. Aucun point, nom, ped ou métier n’est modifiable ici.')}<div class="modal-scroll"><form id="garage-form">${permissionsFields(m.values)}</form></div>${footer('save-permissions','Enregistrer les permissions')}`;}
    if(m.type==='point')return `${header('Ajouter un point de '+(m.kind==='store'?'rangement':'sortie'),'Déplace-toi en jeu et capture la position exacte du nouvel emplacement.')}
      <div class="modal-scroll"><form id="point-form" class="field-grid">${field('label','Nom du point',m.label||'','text','maxlength="40" required')}<div class="field full">${coordsRow('point','Position du point',m.coords)}</div></form><div class="hint-box">Le point doit être capturé à proximité de ton personnage et dans le périmètre du garage.</div></div>${footer('save-point','Ajouter ce point')}`;
    if(m.type==='category'){const c=m.values;return `${header(m.category?'Modifier la catégorie':'Nouvelle catégorie','Restreindre l’accès et les clés aux grades précis ou employés choisis.')}
      <div class="modal-scroll"><form id="category-form" class="field-grid">${field('name','Nom de la catégorie',c.name,'text','maxlength="40" required')}${field('access','Grade minimum de base pour voir',c.access_grade,'number','min="0" max="99" step="1" required')}${field('withdraw','Grade minimum pour SORTIR',c.withdraw_grade,'number','min="0" max="99" step="1" required')}${field('store','Grade minimum pour RANGER',c.store_grade,'number','min="0" max="99" step="1" required')}</form><div class="hint-box">L’autorisation d’accès de catégorie se cumule avec celle du garage, mais les grades/personnes d’une même liste sont des alternatives (OU).</div>${accessEditor('category',c.access_rules,m.roster,'Qui peut voir cette catégorie et recevoir ses clés ?')}</div>${footer('save-category','Enregistrer la catégorie')}`;}
    if(m.type==='withdraw'){const v=g.vehicles.find(x=>+x.id===+m.vehicleId);return `${header('Choisir un point de sortie',v?.label||'Sortie de véhicule')}
      <div class="modal-scroll"><form id="withdraw-form"><div class="field"><label>Emplacement de sortie</label><select class="input" name="pointId"><option value="0">Automatique · premier point libre</option>${(g.spawnPoints||[]).map(p=>`<option value="${p.id}">${e(p.label)} · ${e(formatCoords(p.coords))}</option>`).join('')}</select></div></form><div class="hint-box">Si tu choisis « Automatique », un emplacement libre sera sélectionné côté serveur.</div></div>${footer('confirm-withdraw','Sortir le véhicule')}`;}
    if(m.type==='rename'){const v=g.vehicles.find(x=>+x.id===+m.vehicleId);return `${header('Renommer le véhicule',v?.plate||'Véhicule')}<div class="modal-scroll"><form id="rename-form" class="field-grid">${field('label','Nom affiché dans le garage',v?.label||'','text','maxlength="60" required')}</form><p class="form-help">La plaque et le modèle ne changent pas.</p></div>${footer('confirm-rename','Enregistrer le nom')}`;}
    if(m.type==='assign'){const v=g.vehicles.find(x=>+x.id===+m.vehicleId);return `${header('Classer le véhicule',v?.plate||'Véhicule')}<div class="modal-scroll"><form id="assign-form"><div class="field"><label>Catégorie du véhicule</label>${categorySelect(g,v?.category_id)}</div></form><div class="hint-box">Les permissions de la nouvelle catégorie s’appliqueront immédiatement.</div></div>${footer('confirm-assign','Classer le véhicule')}`;}
    if(m.type==='register')return `${header('Importer depuis un garage externe','Véhicule de société ou personnel autorisé : le transfert le rend disponible à la flotte partagée.')}
      <div class="modal-scroll">${!m.vehicle?`<div class="hint-box">Sors le véhicule d’okokGarage et installe-toi au volant près de ce garage. La plaque et la personnalisation seront récupérées.</div><button class="button primary" data-action="scan-vehicle">${icon('search')} Détecter le véhicule</button>`:
      `<div class="hint-box">${icon('check')} Véhicule détecté : <strong>${e(m.vehicle.plate)}</strong>. L’import le rangera et supprimera son instance du monde.</div><form id="register-form" class="field-grid">${field('label','Nom affiché',m.vehicle.label,'text','maxlength="60" required')}<div class="field"><label>Catégorie de garage</label>${g.abilities.assign_category?categorySelect(g,0):'<span class="form-help">Sans catégorie · classement non autorisé pour ton grade</span>'}</div></form>`}</div><div class="modal-footer"><button class="button" data-action="modal-close">Annuler</button>${m.vehicle?`<button class="button primary" data-action="confirm-register">${icon('upload')} Importer dans la flotte</button>`:''}</div>`;
    const titles={remove:'Retirer ce véhicule ?',recover:'Récupérer ce véhicule ?',delete:'Supprimer ce garage ?',deletePoint:'Supprimer ce point ?',deleteCategory:'Supprimer cette catégorie ?'};
    const messages={remove:'Retire ce véhicule de la flotte du garage, sans supprimer sa propriété. Le véhicule doit être rangé.',recover:'Uniquement si le véhicule a disparu (redémarrage ou despawn), sans duplication d’un véhicule encore présent.',delete:'Le garage et sa flotte seront supprimés. Tous les véhicules doivent être rangés.',deletePoint:'Ce point de sortie ou de rangement sera supprimé. Un point de chaque type doit rester disponible.',deleteCategory:'Les véhicules de cette catégorie seront automatiquement déplacés vers « Sans catégorie ».'};
    return `${header(titles[m.type]||'Confirmer','Action sensible · Contrôle des droits côté serveur')}<div class="modal-scroll"><div class="hint-box alert">${e(messages[m.type]||'Confirmer cette action ?')}</div></div>${footer('confirm-sensitive','Confirmer',m.type!=='recover')}`;
  }
  function renderModal() {
    const layer=$('#modal-layer'), modal=state.modal, shell=$('.shell');
    if(!modal){layer.classList.add('hidden');layer.innerHTML='';if(shell)shell.inert=false;
      const opener=lastRenderedModal?.returnFocus;lastRenderedModal=null;if(state.visible&&opener?.isConnected)opener.focus();return;}
    const same=lastRenderedModal===modal, active=document.activeElement;
    const focusId=same&&layer.contains(active)?active.id:null;
    const snapshot=same?Array.from(layer.querySelectorAll('input[name],select[name],textarea[name]')).map(control=>({name:control.name,value:control.value})):[];
    if(same){if(['create','edit','permissions'].includes(modal.type))captureForm();else if(modal.type==='category')captureCategoryForm();}
    layer.classList.remove('hidden');if(shell)shell.inert=true;
    layer.innerHTML='<div class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title" aria-describedby="modal-description" tabindex="-1">'+modalMarkup()+(modal.error?'<div class="modal-error" id="modal-error" role="alert">'+e(modal.error)+'</div>':'')+'</div>';
    const heading=layer.querySelector('.modal-header h2'), description=layer.querySelector('.modal-header p');
    if(heading)heading.id='modal-title';if(description)description.id='modal-description';
    snapshot.forEach(item=>{const control=Array.from(layer.querySelectorAll('[name]')).find(control=>control.name===item.name);if(control)control.value=item.value;});
    decorateControls();lastRenderedModal=modal;
    if(focusId){const control=$('#'+focusId);if(control)control.focus();}
    else if(!same)(layer.querySelector('input:not([type="checkbox"]),select,button')||layer.querySelector('.modal')).focus();
    if(modal.rosterLoading)layer.querySelectorAll('[data-action="load-staff"]').forEach(button=>button.disabled=true);
    if(busy)layer.querySelectorAll('[data-action]').forEach(button=>{button.dataset.wasDisabled=String(button.disabled);button.disabled=true;});
  }
  function validForm(selector) {
    const form=$(selector);if(!form)return false;
    form.querySelectorAll('input[required]').forEach(input=>{input.setCustomValidity(input.type!=='number'&&!input.value.trim()?'Saisissez une valeur pour ce champ.':'');});
    return form.reportValidity();
  }
  function captureForm(){const form=$('#garage-form');if(!form)return;const v=state.modal.values;const fd=new FormData(form);if(state.modal.type!=='permissions'){v.name=String(fd.get('name')||'');v.job=String(fd.get('job')||'');}for(const k of ['access','withdraw','store','manage','fleet_add','fleet_remove','categories','assign_category','rename'])v.permissions[k]=Number(fd.get(`p_${k}`));v.permissions.access_rules=readRule('garage',v.permissions.access_rules);if(state.modal.type!=='permissions')v.interaction={mode:String(fd.get('interactionMode')||'marker'),pedModel:String(fd.get('pedModel')||'s_m_m_security_01'),scenario:String(fd.get('scenario')||'WORLD_HUMAN_CLIPBOARD')};}
  function captureCategoryForm(){const form=$('#category-form');if(!form)return;const m=state.modal;const fd=new FormData(form);m.values.name=String(fd.get('name')||'');for(const k of ['access','withdraw','store'])m.values[k+'_grade']=Number(fd.get(k));m.values.access_rules=readRule('category',m.values.access_rules);}
  async function capturePosition(target){
    if(busy || !state.modal)return;
    if(['create','edit','permissions'].includes(state.modal.type))captureForm();
    if(state.modal.type==='point')state.modal.label=readForm('#point-form').label||state.modal.label;
    const modal=state.modal,epoch=uiEpoch;setBusy(true);
    try {
      const response=await request('selectPosition');
      if(epoch!==uiEpoch||state.modal!==modal||response.stale)return;
      if(!response.ok){showError(response.error||'Capture impossible. Réessayez en jeu.');return;}
      if(modal.type==='point')modal.coords=response.position;else modal.values[target]=response.position;
      renderModal();toast('Position enregistrée.');
    } finally {if(epoch===uiEpoch)setBusy(false);}
  }

  function openGarageForm(edit=false){const g=garage();const base=edit?deepCopy(g):{name:'',job:state.data.playerJob==='unemployed'?'':state.data.playerJob,permissions:defaultPermissions(),entrance:null,spawn:null,interaction:{mode:'marker',pedModel:'s_m_m_security_01',scenario:'WORLD_HUMAN_CLIPBOARD'}};base.interaction=base.interaction||{mode:'marker',pedModel:'s_m_m_security_01',scenario:'WORLD_HUMAN_CLIPBOARD'};base.permissions.access_rules=normalizedRule(base.permissions.access_rules);openModal(edit?'edit':'create',{values:base});const modal=state.modal;loadRoster(modal);if(!edit)request('capturePosition').then(r=>{if(r.ok&&state.modal===modal){state.modal.values.entrance=r.position;state.modal.values.spawn=r.position;renderModal();}});}
  function readForm(sel){const element=$(sel);return element?Object.fromEntries(new FormData(element).entries()):{};}

  document.addEventListener('click',async(event)=>{
    const button=event.target.closest('[data-action]');if(!button||busy)return;
    const action=button.dataset.action;const g=garage();const id=Number(button.dataset.vehicle);
    const forms={'save-garage':'#garage-form','save-permissions':'#garage-form','save-point':'#point-form','save-category':'#category-form','confirm-rename':'#rename-form','confirm-register':'#register-form'};
    if(forms[action]&&!validForm(forms[action]))return;
    if(action==='reload'){await reload();return;}
    if(action==='clear-filters'){state.search='';state.statusFilter='all';state.categoryFilter='all';render();$('#fleet-search')?.focus();return;}
    if(action==='overview'){if(state.data.singleGarage)return;state.view='overview';render();return;}
    if(action==='garage'){if(state.data.singleGarage&&Number(button.dataset.id)!==Number(state.selectedId))return;openSelect(button.dataset.id);return;}
    if(action==='select-first'){if(state.data.garages.length)openSelect(state.selectedId || state.data.garages[0].id);return;}
    if(action==='tab-fleet'){setTab('fleet');return;}if(action==='tab-categories'){setTab('categories');return;}if(action==='tab-settings'){setTab('settings');return;}
    if(action==='new-garage'){openGarageForm();return;}
    if(action==='edit-garage'){if(!g?.abilities.structure)return;openGarageForm(true);return;}
    if(action==='edit-permissions'){if(!g?.abilities.manage)return;openModal('permissions',{values:deepCopy(g)});loadRoster(state.modal);return;}
    if(action==='save-permissions'){captureForm();await perform('updateGaragePermissions',{garageId:g.id,permissions:state.modal.values.permissions});return;}
    if(action==='modal-close'){state.modal=null;renderModal();return;}
    if(action==='capture'){await capturePosition(button.dataset.field);return;}
    if(action==='load-staff'){if(['create','edit','permissions'].includes(state.modal?.type))captureForm();else if(state.modal?.type==='category')captureCategoryForm();if(state.modal)await loadRoster(state.modal);return;}
    if(action==='save-garage'){captureForm();const m=state.modal;const v=m.values;if(!v.entrance||(m.type==='create'&&!v.spawn)){toast('Capturez les emplacements requis.',true);return;}await perform(m.type==='edit'?'updateGarage':'createGarage',{id:v.id,name:v.name,job:v.job,entrance:v.entrance,spawn:v.spawn,permissions:v.permissions,interaction:v.interaction},(r)=>{if(m.type==='create'&&r.id)openSelect(r.id);});return;}
    if(action==='add-point'){if(!g?.abilities.structure)return;openModal('point',{kind:button.dataset.kind,coords:null,label:button.dataset.kind==='spawn'?'Nouvelle sortie':'Nouveau rangement'});return;}
    if(action==='save-point'){const form=readForm('#point-form');if(!state.modal.coords){toast('Capture le point en jeu.',true);return;}await perform('addPoint',{garageId:g.id,kind:state.modal.kind,label:form.label,coords:state.modal.coords});return;}
    if(action==='remove-point'){if(!g?.abilities.structure)return;openModal('deletePoint',{pointId:Number(button.dataset.point)});return;}
    if(action==='new-category'){openModal('category',{category:null,values:{name:'',access_grade:0,withdraw_grade:0,store_grade:0,access_rules:defaultRule()}});loadRoster(state.modal);return;}
    if(action==='edit-category'){const category=deepCopy(g.categories.find(c=>+c.id===+button.dataset.category));openModal('category',{category,values:{...category,access_rules:normalizedRule(category.access_rules)}});loadRoster(state.modal);return;}
    if(action==='delete-category'){openModal('deleteCategory',{categoryId:Number(button.dataset.category)});return;}
    if(action==='save-category'){captureCategoryForm();const c=state.modal.values;await perform('saveCategory',{garageId:g.id,categoryId:state.modal.category?.id||0,name:c.name,grades:{access:c.access_grade,withdraw:c.withdraw_grade,store:c.store_grade,access_rules:c.access_rules}});return;}
    if(action==='rename-vehicle'){openModal('rename',{vehicleId:id});return;}
    if(action==='confirm-rename'){const form=readForm('#rename-form');await perform('renameVehicle',{garageId:g.id,vehicleId:state.modal.vehicleId,label:form.label});return;}
    if(action==='classify-vehicle'){openModal('assign',{vehicleId:id});return;}
    if(action==='confirm-assign'){const form=readForm('#assign-form');await perform('assignCategory',{garageId:g.id,vehicleId:state.modal.vehicleId,categoryId:Number(form.categoryId)});return;}
    if(action==='confirm-withdraw'){const form=readForm('#withdraw-form');await perform('withdraw',{garageId:g.id,vehicleId:state.modal.vehicleId,pointId:Number(form.pointId)});return;}
    if(action==='register'){openModal('register');return;}
    if(action==='scan-vehicle'){
      const modal=state.modal,epoch=uiEpoch;if(!modal)return;setBusy(true);
      try {const response=await request('captureVehicle');if(epoch!==uiEpoch||state.modal!==modal||response.stale)return;if(!response.ok){showError(response.error);return;}modal.vehicle=response;renderModal();}
      finally {if(epoch===uiEpoch)setBusy(false);}return;
    }
    if(action==='confirm-register'){const v=state.modal.vehicle;const form=readForm('#register-form');const categoryId=Number(form.categoryId)||0;await perform('registerVehicle',{garageId:g.id,netId:v.netId,props:v.props,vehicleType:v.vehicleType,label:form.label,categoryId});return;}
    if(action==='withdraw'){openModal('withdraw',{vehicleId:id});return;}
    if(action==='store'){const payload={garageId:g.id};if(button.dataset.vehicle)payload.vehicleId=id;await mutate(()=>request('storeCurrent',payload));return;}
    if(action==='recover'){openModal('recover',{vehicleId:id});return;}
    if(action==='remove-vehicle'){openModal('remove',{vehicleId:id});return;}
    if(action==='delete-garage'){if(!g?.abilities.structure)return;openModal('delete');return;}
    if(action==='confirm-sensitive'){const m=state.modal;const next=m.type==='remove'?'removeVehicle':m.type==='recover'?'recover':m.type==='deletePoint'?'removePoint':m.type==='deleteCategory'?'deleteCategory':'deleteGarage';
      const payload=m.type==='delete'?{id:g.id}:m.type==='deletePoint'?{garageId:g.id,pointId:m.pointId}:m.type==='deleteCategory'?{garageId:g.id,categoryId:m.categoryId}:{garageId:g.id,vehicleId:m.vehicleId};
      await perform(next,payload,()=>{if(m.type==='delete'){state.view='overview';state.selectedId=null;render();}});return;}
  });
  document.addEventListener('input',(ev)=>{
    if(ev.target.setCustomValidity)ev.target.setCustomValidity('');
    if(ev.target.matches('[data-search-acl]')){
      const q=ev.target.value.toLowerCase().trim();
      const parent=ev.target.closest('.acl-editor');
      parent?.querySelectorAll('[data-person-search]').forEach(el=>{el.hidden=!el.dataset.personSearch.includes(q);});
    }
    if(ev.target.id==='fleet-search'){const start=ev.target.selectionStart;state.search=ev.target.value;renderGarage();const el=$('#fleet-search');if(el){el.focus();try{el.setSelectionRange(start,start)}catch{}}}
  });
  document.addEventListener('change',(ev)=>{
    if(ev.target.classList?.contains('acl-mode')){
      if(['create','edit','permissions'].includes(state.modal?.type))captureForm();
      if(state.modal?.type==='category')captureCategoryForm();
      renderModal();return;
    }
    if(ev.target.id==='fleet-filter'){state.statusFilter=ev.target.value;renderGarage();}if(ev.target.id==='fleet-category'){state.categoryFilter=ev.target.value;renderGarage();}});
  $('#refresh-button').innerHTML=icon('refresh');$('#close-button').innerHTML=icon('close');
  $('#refresh-button').addEventListener('click',()=>{if(!busy)reload();});
  function closeUi(notify=false){
    state.visible=false;state.modal=null;invalidateSession();renderModal();$('#app').classList.add('hidden');
    if(notify)request('close');
  }
  $('#close-button').addEventListener('click',()=>closeUi(true));
  document.addEventListener('submit',event=>{
    if(!state.modal||!event.target.closest('#modal-layer'))return;
    event.preventDefault();$('#modal-layer').querySelector('.modal-footer button:last-child')?.click();
  });
  window.addEventListener('keydown',event=>{
    if(!state.visible)return;
    if(event.key==='Escape'){event.preventDefault();if(state.modal&&!busy){state.modal=null;renderModal();}else if(!state.modal)closeUi(true);return;}
    if(event.key==='Tab'&&state.modal){
      const nodes=Array.from($('#modal-layer').querySelectorAll('button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex="0"]')).filter(node=>!node.closest('[hidden]'));
      if(!nodes.length){event.preventDefault();$('#modal-layer').querySelector('.modal')?.focus();return;}
      const first=nodes[0],last=nodes[nodes.length-1];
      if(event.shiftKey&&(document.activeElement===first||!$('#modal-layer').contains(document.activeElement))){event.preventDefault();last.focus();}
      else if(!event.shiftKey&&(document.activeElement===last||!$('#modal-layer').contains(document.activeElement))){event.preventDefault();first.focus();}
    }
  });
  window.addEventListener('message',event=>{
    const msg=event.data;if(!msg||typeof msg!=='object')return;
    if(msg.type==='open'){
      if(msg.sessionId!==undefined&&activeSession!==null&&Number(msg.sessionId)<activeSession)return;
      invalidateSession(msg.sessionId===undefined?null:Number(msg.sessionId));
      state.visible=true;state.loading=IS_FIVEM;state.loadError='';state.view='overview';state.modal=null;
      state.search='';state.statusFilter='all';state.categoryFilter='all';state.tab='fleet';state.selectedId=null;
      state.pendingSelectedId=msg.selectedId?Number(msg.selectedId):null;
      if(IS_FIVEM){state.data=blankData();state.selectedId=null;}
      $('#app').classList.remove('hidden');render();return;
    }
    if(msg.sessionId!==undefined&&activeSession!==null&&Number(msg.sessionId)!==activeSession)return;
    if(msg.type==='close'){closeUi();return;}
    if(!state.visible)return;
    if(msg.type==='bootstrap'){
      if(!msg.payload||typeof msg.payload!=='object'||msg.payload.ok===false){state.loading=false;state.loadError=msg.payload?.error||'Actualisez pour réessayer.';render();return;}
      reloadSequence++;state.loading=false;state.loadError='';state.data=normalizeData(msg.payload);
      if(state.pendingSelectedId){state.selectedId=state.pendingSelectedId;state.view='garage';state.tab='fleet';state.pendingSelectedId=null;}
      if(state.selectedId&&!garage()){state.selectedId=null;state.view='overview';}
      if(!state.selectedId&&state.data.garages.length)state.selectedId=state.data.garages[0].id;
      if(state.data.singleGarage){state.view='garage';state.selectedId=state.data.garages[0]?.id||null;}
      render();return;
    }
    if(msg.type==='captureStart')$('#app').classList.add('hidden');
    if(msg.type==='captureEnd')$('#app').classList.remove('hidden');
  });
  if (!IS_FIVEM && window.EnterpriseGaragePreview) window.EnterpriseGaragePreview.open();
})();
