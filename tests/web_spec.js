'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../web/app.js'), 'utf8');

function harness(fivem = true) {
  const requests = [], timers = new Map(), listeners = {}, nodes = new Map();
  let timerId = 0, document;
  class Node {
    constructor(name = '') {this.name=name;this.id=name.startsWith('#')?name.slice(1):'';this.children=[];this.dataset={};this.attrs={};this.disabled=false;this.isConnected=true;this.handlers={};this.innerHTML='';this.textContent='';this.value='';this.title='';this.controls=[];this.form=null;const classes=new Set();this.classList={add:x=>classes.add(x),remove:x=>classes.delete(x),contains:x=>classes.has(x),toggle:(x,on)=>on?classes.add(x):classes.delete(x)};}
    setAttribute(k,v){this.attrs[k]=String(v);}
    getAttribute(k){return this.attrs[k];}
    hasAttribute(k){return k in this.attrs;}
    removeAttribute(k){delete this.attrs[k];}
    addEventListener(k,v){this.handlers[k]=v;}
    appendChild(n){n.parentElement=this;this.children.push(n);return n;}
    prepend(n){this.children.unshift(n);}
    remove(){if(this.parentElement)this.parentElement.children=this.parentElement.children.filter(n=>n!==this);}
    get firstElementChild(){return this.children[0];}
    closest(sel){if(sel==='[data-action]'&&this.dataset.action)return this;if(sel==='#modal-layer'&&this.inModal)return nodes.get('#modal-layer');if(sel==='[hidden]')return null;return null;}
    querySelector(sel){if(sel==='.modal-header h2'||sel==='.modal-header p'||sel==='.modal')return this.dialogPart||(this.dialogPart=new Node(sel));if(sel==='input:not([type="checkbox"]),select,button')return this.controls[0]||this.dialogPart||(this.dialogPart=new Node('dialog'));return null;}
    querySelectorAll(sel){if(sel.startsWith('button:not'))return this.controls;if(sel.includes('[name]'))return [];return [];}
    contains(node){return node?.inModal||this.controls.includes(node)||node===this.dialogPart;}
    focus(){document.activeElement=this;}
    click(){return this.handlers.click?.({target:this,currentTarget:this});}
    matches(sel){return sel==='[data-search-acl]'?false:false;}
  }
  for(const name of ['#app','#nav-primary','#nav-garages','#profile-name','#profile-job','#avatar','#role-chip','#breadcrumb-current','#content','#scroll-content','#toast-area','#modal-layer','#refresh-button','#close-button','#operation-status','.shell'])nodes.set(name,new Node(name));
  const buttons=[];
  document={activeElement:null,querySelector:sel=>nodes.get(sel)||null,querySelectorAll:sel=>sel==='[data-action]'?buttons:[],createElement:tag=>new Node(tag),addEventListener:(name,fn)=>listeners['document:'+name]=fn};
  document.activeElement=nodes.get('#refresh-button');
  const sandbox={document,AbortController,FormData,console,setTimeout:(fn,ms)=>{const id=++timerId;timers.set(id,{fn,ms});return id;},clearTimeout:id=>timers.delete(id),fetch:(url,options)=>new Promise((resolve,reject)=>{const entry={name:url.split('/').pop(),body:JSON.parse(options.body),options,resolve:value=>resolve({ok:true,json:async()=>value}),httpFail:()=>resolve({ok:false}),reject};options.signal.addEventListener('abort',()=>reject(new Error('Aborted')));requests.push(entry);})};
  sandbox.window={addEventListener:(name,fn)=>listeners['window:'+name]=fn};
  if(fivem)sandbox.GetParentResourceName=()=> 'aegis_enterprise_garages';
  vm.createContext(sandbox);
  vm.runInContext(source,sandbox,{filename:'web/app.js'});
  const message=data=>listeners['window:message']({data});
  const action=async(name,data={})=>{const button=new Node('button');button.dataset={action:name,...data};buttons.push(button);document.activeElement=button;await listeners['document:click']({target:button});return button;};
  const key=(key,shiftKey=false)=>{let prevented=false;listeners['window:keydown']({key,shiftKey,preventDefault:()=>prevented=true});return prevented;};
  const refresh=()=>nodes.get('#refresh-button').click();
  return {requests,timers,nodes,listeners,document,Node,message,action,key,refresh};
}
const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};
const garage=(name='Mission Row',stored=true)=>({id:1,name,job:'police',permissions:{},abilities:{store:true,structure:true},vehicles:[{id:10,label:'Véhicule <script>alert(1)</script>',model:'police',plate:'LSPD 001',stored,canWithdraw:true,canStore:true}],categories:[],spawnPoints:[{id:1,label:'Sortie',coords:{x:1,y:2,z:3}}],storePoints:[]});
const data=(name='Mission Row',stored=true)=>({ok:true,garages:[garage(name,stored)],playerLabel:'Alex',playerJob:'police',grade:4,isAdmin:true});
function bootstrap(h,session,name,selected=false,stored=true){h.message({type:'open',sessionId:session,selectedId:selected?1:null});h.message({type:'bootstrap',sessionId:session,payload:data(name,stored)});}

async function run(){
  {
    const h=harness();h.message({type:'open',sessionId:20});
    assert.match(h.nodes.get('#content').innerHTML,/Chargement des garages/);
    h.message({type:'bootstrap',sessionId:19,payload:data('Obsolete')});
    assert.doesNotMatch(h.nodes.get('#content').innerHTML,/Obsolete/);
    h.message({type:'bootstrap',sessionId:20,payload:{garages:null,playerLabel:{},playerJob:12}});
    assert.match(h.nodes.get('#content').innerHTML,/Aucun garage accessible/);
    h.message({type:'bootstrap',sessionId:20,payload:data('<img src=x onerror=alert(1)>')});
    assert.match(h.nodes.get('#nav-garages').innerHTML,/&lt;img/);
    assert.doesNotMatch(h.nodes.get('#nav-garages').innerHTML,/<img/);
    h.refresh();h.refresh();await flush();assert.equal(h.requests.length,2);
    assert.equal(h.requests[0].body.uiSession,20);
    h.requests[1].resolve(data('Latest'));await flush();
    h.requests[0].resolve(data('Old'));await flush();
    assert.match(h.nodes.get('#content').innerHTML,/Latest/);assert.doesNotMatch(h.nodes.get('#content').innerHTML,/Old/);
    assert.equal(h.nodes.get('#app').getAttribute('aria-busy'),'false');
  }
  {
    const h=harness();bootstrap(h,30,'First');h.refresh();await flush();const old=h.requests[0];
    bootstrap(h,31,'Second');await flush();assert.equal(old.options.signal.aborted,true);
    old.resolve(data('Old session'));await flush();assert.match(h.nodes.get('#content').innerHTML,/Second/);
    h.message({type:'captureStart',sessionId:30});assert.equal(h.nodes.get('#app').classList.contains('hidden'),false);
    h.message({type:'close',sessionId:31});h.message({type:'captureEnd',sessionId:31});assert.equal(h.nodes.get('#app').classList.contains('hidden'),true);
    h.message({type:'open',sessionId:32});assert.doesNotMatch(h.nodes.get('#content').innerHTML,/Second/);
  }
  {
    const h=harness();bootstrap(h,40,'Fleet',true,0);
    assert.match(h.nodes.get('#content').innerHTML,/En circulation/);assert.match(h.nodes.get('#content').innerHTML,/&lt;script&gt;/);
    const first=h.action('store',{vehicle:'10'});await flush();
    await h.action('store',{vehicle:'10'});assert.equal(h.requests.filter(r=>r.name==='storeCurrent').length,1);
    assert.equal(h.nodes.get('#refresh-button').disabled,true);
    h.requests[0].resolve({ok:false,error:'Véhicule trop loin'});await first;await flush();
    assert.equal(h.nodes.get('#refresh-button').disabled,false);assert.match(h.nodes.get('#toast-area').children[0].innerHTML,/Véhicule trop loin/);
    const retry=h.action('store',{vehicle:'10'});await flush();h.requests[1].resolve({ok:true,message:'Rangé'});await flush();
    assert.equal(h.requests[2].name,'fetchData');await h.action('store',{vehicle:'10'});assert.equal(h.requests.length,3);
    h.requests[2].resolve(data('Fleet',true));await retry;await flush();assert.equal(h.nodes.get('#refresh-button').disabled,false);
    await h.action('add-point',{kind:'spawn'});const layer=h.nodes.get('#modal-layer');assert.match(layer.innerHTML,/role="dialog"/);assert.equal(h.nodes.get('.shell').inert,true);
    const firstControl=new h.Node('first'),lastControl=new h.Node('last');firstControl.inModal=true;lastControl.inModal=true;layer.controls=[firstControl,lastControl];lastControl.focus();
    assert.equal(h.key('Tab'),true);assert.equal(h.document.activeElement,firstControl);assert.equal(h.key('Tab',true),true);assert.equal(h.document.activeElement,lastControl);
    const capture=h.action('capture',{field:'point'});await flush();assert.equal(h.requests[3].name,'selectPosition');assert.equal([...h.timers.values()].some(timer=>timer.ms===130000),true);
    await h.action('capture',{field:'point'});assert.equal(h.requests.length,4);
    h.nodes.get('#close-button').click();await capture;await flush();assert.equal(h.requests[3].options.signal.aborted,true);assert.equal(h.nodes.get('.shell').inert,false);
  }
  {
    const h=harness();bootstrap(h,50,'Resilient');h.refresh();await flush();h.requests[0].resolve({unexpected:true});await flush();
    assert.match(h.nodes.get('#toast-area').children[0].innerHTML,/Réponse du garage invalide/);assert.equal(h.nodes.get('#refresh-button').disabled,false);
    h.refresh();await flush();const timeout=[...h.timers.values()].find(timer=>timer.ms===20000);timeout.fn();await flush();
    assert.equal(h.requests[1].options.signal.aborted,true);assert.match(h.nodes.get('#toast-area').children.at(-1).innerHTML,/trop de temps/);assert.equal(h.nodes.get('#refresh-button').disabled,false);
  }
  {
    const h=harness(false);
    assert.equal(h.nodes.get('#content').innerHTML,'');
    assert.equal(h.nodes.get('#nav-garages').innerHTML,'');
    bootstrap(h,60,'Fleet',true,0);
    await h.action('store',{vehicle:'10'});await flush();
    assert.equal(h.requests.length,0);
    assert.match(h.nodes.get('#toast-area').children[0].innerHTML,/ouverte depuis FiveM/);
  }
  console.log('PASS web_spec: session isolation, request ordering, loading/error recovery, escaped data, mutation locking, dialog keyboard and FiveM-only transport');
}
run().catch(error=>{console.error(error);process.exitCode=1;});
