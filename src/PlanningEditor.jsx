import React,{useEffect,useMemo,useState} from 'react';
import {supabase} from './supabase';
import {jsPDF} from 'jspdf';
import * as XLSX from 'xlsx';
import './planning.css';

const uid=()=>crypto.randomUUID();
const roles=['Liderança geral','Mesa','Frios','Líder de pré-contagem','Coordenação do turno noturno','Coordenador líder','Coordenador','Apoio','Conferente','Líder de perecíveis'];
const activities=['Coleta das gavetas','Coleta de picking','Coleta de aéreo','Coleta de subaéreo','Coleta de produtos para pesagem/balança','Mapeamento do piso de vendas','Auditoria e ajuste das gavetas'];
const equipment=['Empilhadeira','Escada','Rádio comunicador','Coletor de dados','Notebook','Impressora','Balança','EPI perecível','Ônibus','Micro-ônibus','Van'];
const checklistLabels={preInventory:'Visita pré-inventário',planning:'Planejamento',final:'Aprovação final'};
const planningColumns=[{key:'received',label:'Entrada',statuses:['received']},{key:'dimensioning',label:'Dimensionamento',statuses:['awaiting_dimensioning']},{key:'ti',label:'TI / Datas',statuses:['awaiting_ti','awaiting_dates']},{key:'planning',label:'Em planejamento',statuses:['planning']},{key:'done',label:'Concluídos',statuses:['confirmed']}];
const planningStatus={received:'Entrada',awaiting_dimensioning:'Dimensionamento',awaiting_ti:'TI / Datas',awaiting_dates:'Datas enviadas',planning:'Planejamento',confirmed:'Concluído'};
const responsibilityRows=()=>['Liderança geral','Mesa','Frios','Líder de pré-contagem','Coordenação do turno noturno'].map(role=>({id:uid(),role,person:'',notes:''}));
const area=(kind='Depósito')=>{const base={id:uid(),name:kind,shift:'',startsAt:'',headcount:'',notes:'',roles:[],activities:[]};if(kind==='Depósito')return {...base,roles:[{id:uid(),role:'Coordenador líder',count:'',names:''},{id:uid(),role:'Coordenador',count:'',names:''},{id:uid(),role:'Apoio',count:'',names:''},{id:uid(),role:'Conferente',count:'',names:''}],activities:['Coleta das gavetas','Coleta de picking','Coleta de aéreo','Coleta de subaéreo'].map(name=>({id:uid(),name,notes:''}))};if(kind==='Câmaras')return {...base,roles:[{id:uid(),role:'Líder de perecíveis',count:'',names:''},{id:uid(),role:'Conferente',count:'',names:''}],activities:['Coleta de aéreo','Coleta de subaéreo','Coleta de picking','Coleta de produtos para pesagem/balança'].map(name=>({id:uid(),name,notes:''}))};if(kind==='Coordenação')return {...base,roles:[{id:uid(),role:'Coordenação',count:'',names:''}],activities:[]};if(kind==='Divisão da equipe')return {...base,roles:[{id:uid(),role:'Conferente',count:'',names:''}],activities:[]};return base};
const day=(date='')=>({id:uid(),date,headcount:'',notes:'',areas:[]});
const initial=()=>({store:{unit:'',preCountEnabled:false,preStart:'',preEnd:'',inventoryStart:'',inventoryEnd:'',headcount:''},responsibilities:responsibilityRows(),logistics:{transports:[],accommodations:[],notes:''},clientEquipment:{rows:[],notes:''},contagemEquipment:{rows:[],notes:''},preCount:{rows:[],notes:''},days:[],completedBlocks:{},checklists:{preInventory:[{id:uid(),label:'Visita pré-inventário realizada',done:false},{id:uid(),label:'Layout, áreas e acessos validados',done:false},{id:uid(),label:'Contato da loja e responsáveis confirmados',done:false}],planning:[{id:uid(),label:'Responsáveis definidos',done:false},{id:uid(),label:'Logística revisada',done:false},{id:uid(),label:'Equipamentos confirmados',done:false},{id:uid(),label:'Horários de alimentação definidos',done:false}],final:[{id:uid(),label:'Planejamento revisado',done:false},{id:uid(),label:'Pendências críticas resolvidas',done:false},{id:uid(),label:'Aprovação do supervisor',done:false}]}});
const merge=(value)=>{const defaults=initial();const days=Array.isArray(value?.days)?value.days.map(dayItem=>({...day(),...dayItem,areas:Array.isArray(dayItem?.areas)?dayItem.areas.map(areaItem=>({...areaItem,roles:Array.isArray(areaItem?.roles)?areaItem.roles:[],activities:Array.isArray(areaItem?.activities)?areaItem.activities:[]})):[]})):[];return {...defaults,...(value||{}),completedBlocks:{...defaults.completedBlocks,...(value?.completedBlocks||{})},responsibilities:Array.isArray(value?.responsibilities)&&value.responsibilities.length?value.responsibilities:defaults.responsibilities,store:{...defaults.store,...(value?.store||{})},logistics:{...defaults.logistics,...(value?.logistics||{}),transports:Array.isArray(value?.logistics?.transports)?value.logistics.transports:[],accommodations:Array.isArray(value?.logistics?.accommodations)?value.logistics.accommodations:[]},clientEquipment:{...defaults.clientEquipment,...(value?.clientEquipment||{}),rows:Array.isArray(value?.clientEquipment?.rows)?value.clientEquipment.rows:[]},contagemEquipment:{...defaults.contagemEquipment,...(value?.contagemEquipment||{}),rows:Array.isArray(value?.contagemEquipment?.rows)?value.contagemEquipment.rows:[]},preCount:{...defaults.preCount,...(value?.preCount||{}),rows:Array.isArray(value?.preCount?.rows)?value.preCount.rows:[]},days,checklists:{preInventory:Array.isArray(value?.checklists?.preInventory)?value.checklists.preInventory:defaults.checklists.preInventory,planning:Array.isArray(value?.checklists?.planning)?value.checklists.planning:defaults.checklists.planning,final:Array.isArray(value?.checklists?.final)?value.checklists.final:defaults.checklists.final}}};

const hasValue=value=>value!==null&&value!==undefined&&(typeof value!=='string'||value.trim()!=='');
const isPositive=value=>hasValue(value)&&Number.isInteger(Number(value))&&Number(value)>0;
const hasRowData=(item,ignored=['id'])=>Boolean(item&&Object.entries(item).some(([key,value])=>!ignored.includes(key)&&(Array.isArray(value)?value.length>0:typeof value==='boolean'?value:hasValue(value))));
const addCheck=(checks,label,ok)=>checks.push({label,ok:Boolean(ok)});
const makeBlock=(key,label,checks,applicable=true)=>{const completed=checks.filter(check=>check.ok).length;const percentage=!applicable||!checks.length?100:Math.round(completed/checks.length*100);return {key,label,checks,applicable,percentage,issues:applicable?checks.filter(check=>!check.ok).map(check=>check.label):[]}};
const dateIsBetween=(date,start,end)=>!date||!start||!end||(date>=start&&date<=end);
const unique=list=>[...new Set(list)];

export function auditPlanning(content){
  const blocks=[];
  const validationErrors=[];
  const store=content.store||{};

  const storeChecks=[];
  addCheck(storeChecks,'Informar a unidade da loja.',hasValue(store.unit));
  addCheck(storeChecks,'Informar uma quantidade positiva para o efetivo geral.',isPositive(store.headcount));
  addCheck(storeChecks,'Informar a data inicial do inventário.',hasValue(store.inventoryStart));
  addCheck(storeChecks,'Informar a data final do inventário.',hasValue(store.inventoryEnd));
  addCheck(storeChecks,'Manter o início do inventário anterior ou igual ao fim.',store.inventoryStart&&store.inventoryEnd&&store.inventoryStart<=store.inventoryEnd);
  blocks.push(makeBlock('store','Loja',storeChecks));
  if(store.inventoryStart&&store.inventoryEnd&&store.inventoryStart>store.inventoryEnd)validationErrors.push('A data inicial do inventário deve ser anterior ou igual à data final.');
  if(hasValue(store.headcount)&&!isPositive(store.headcount))validationErrors.push('O efetivo geral deve ser maior que zero.');

  const responsibilityChecks=[];
  const responsibilities=Array.isArray(content.responsibilities)?content.responsibilities:[];
  addCheck(responsibilityChecks,'Cadastrar ao menos um responsável com função e nome.',responsibilities.some(row=>hasValue(row.role)&&hasValue(row.person)));
  responsibilities.forEach((row,index)=>{
    const description=row.role?.trim()||`linha ${index+1}`;
    addCheck(responsibilityChecks,`Informar a função do responsável na ${description}.`,hasValue(row.role));
    addCheck(responsibilityChecks,`Informar o responsável por ${description}.`,hasValue(row.person));
  });
  blocks.push(makeBlock('responsibilities','Responsáveis',responsibilityChecks));

  const logistics=content.logistics||{transports:[],accommodations:[],notes:''};
  const transports=Array.isArray(logistics.transports)?logistics.transports:[];
  const accommodations=Array.isArray(logistics.accommodations)?logistics.accommodations:[];
  const logisticsApplicable=transports.length>0||accommodations.length>0||hasValue(logistics.notes);
  const operationalStart=store.preCountEnabled&&store.preStart?store.preStart:store.inventoryStart;
  const operationalEnd=store.inventoryEnd;
  const logisticsChecks=[];
  transports.forEach((row,index)=>{
    const prefix=`Transporte ${index+1}`;
    addCheck(logisticsChecks,`${prefix}: informar data.`,hasValue(row.date));
    addCheck(logisticsChecks,`${prefix}: informar horário.`,hasValue(row.time));
    addCheck(logisticsChecks,`${prefix}: informar trajeto.`,hasValue(row.route));
    addCheck(logisticsChecks,`${prefix}: informar passageiros.`,hasValue(row.passengers));
    addCheck(logisticsChecks,`${prefix}: informar quantidade positiva.`,isPositive(row.quantity));
    if(hasValue(row.quantity)&&!isPositive(row.quantity))validationErrors.push(`${prefix}: a quantidade deve ser maior que zero.`);
    if(row.date&&operationalStart&&operationalEnd&&!dateIsBetween(row.date,operationalStart,operationalEnd))validationErrors.push(`${prefix}: a data deve estar dentro do período operacional (pré-contagem + inventário).`);
  });
  accommodations.forEach((row,index)=>{
    const prefix=`Hospedagem ${index+1}`;
    addCheck(logisticsChecks,`${prefix}: informar hóspedes.`,hasValue(row.guests));
    addCheck(logisticsChecks,`${prefix}: informar quartos.`,hasValue(row.rooms));
    addCheck(logisticsChecks,`${prefix}: informar entrada.`,hasValue(row.checkIn));
    addCheck(logisticsChecks,`${prefix}: informar saída.`,hasValue(row.checkOut));
    addCheck(logisticsChecks,`${prefix}: informar quantidade positiva de hóspedes.`,isPositive(row.count));
    if(row.checkIn&&row.checkOut&&row.checkIn>row.checkOut)validationErrors.push(`${prefix}: a entrada deve ser anterior ou igual à saída.`);
    if(hasValue(row.count)&&!isPositive(row.count))validationErrors.push(`${prefix}: a quantidade de hóspedes deve ser maior que zero.`);
  });
  if(logisticsApplicable&&!logisticsChecks.length)addCheck(logisticsChecks,'Orientações gerais de logística registradas.',hasValue(logistics.notes));
  blocks.push(makeBlock('logistics','Logística',logisticsChecks,logisticsApplicable));

  const equipmentChecks=[];
  let equipmentApplicable=false;
  ;[['clientEquipment','Equipamentos do cliente'],['contagemEquipment','Equipamentos Contagem']].forEach(([key,label])=>{
    const group=content[key]||{rows:[],notes:''};
    const rows=Array.isArray(group.rows)?group.rows:[];
    const groupApplicable=rows.length>0||hasValue(group.notes);
    equipmentApplicable=equipmentApplicable||groupApplicable;
    rows.forEach((row,index)=>{
      const prefix=`${label}, item ${index+1}`;
      addCheck(equipmentChecks,`${prefix}: informar equipamento.`,hasValue(row.equipment));
      addCheck(equipmentChecks,`${prefix}: informar dia.`,hasValue(row.date));
      addCheck(equipmentChecks,`${prefix}: informar turno.`,hasValue(row.shift));
      addCheck(equipmentChecks,`${prefix}: informar quantidade positiva.`,isPositive(row.quantity));
      addCheck(equipmentChecks,`${prefix}: informar status.`,hasValue(row.status));
      if(hasValue(row.quantity)&&!isPositive(row.quantity))validationErrors.push(`${prefix}: a quantidade deve ser maior que zero.`);
      if(row.date&&store.inventoryStart&&store.inventoryEnd&&!dateIsBetween(row.date,store.inventoryStart,store.inventoryEnd))validationErrors.push(`${prefix}: a data deve estar dentro do período do inventário.`);
    });
    if(groupApplicable&&!rows.length)addCheck(equipmentChecks,`${label}: detalhes gerais registrados.`,hasValue(group.notes));
  });
  blocks.push(makeBlock('equipment','Equipamentos',equipmentChecks,equipmentApplicable));

  const preCountChecks=[];
  if(store.preCountEnabled){
    addCheck(preCountChecks,'Informar o início da pré-contagem.',hasValue(store.preStart));
    addCheck(preCountChecks,'Informar o fim da pré-contagem.',hasValue(store.preEnd));
    addCheck(preCountChecks,'Manter o início da pré-contagem anterior ou igual ao fim.',store.preStart&&store.preEnd&&store.preStart<=store.preEnd);
    const rows=content.preCount?.rows||[];
    addCheck(preCountChecks,'Cadastrar ao menos uma equipe de pré-contagem.',rows.length>0);
    rows.forEach((row,index)=>{
      const prefix=`Pré-contagem ${index+1}`;
      addCheck(preCountChecks,`${prefix}: informar data.`,hasValue(row.date));
      addCheck(preCountChecks,`${prefix}: informar horário.`,hasValue(row.time));
      addCheck(preCountChecks,`${prefix}: informar equipe.`,hasValue(row.team));
      addCheck(preCountChecks,`${prefix}: informar quantidade positiva de pessoas.`,isPositive(row.count));
      if(hasValue(row.count)&&!isPositive(row.count))validationErrors.push(`${prefix}: a quantidade de pessoas deve ser maior que zero.`);
      if(row.date&&store.preStart&&store.preEnd&&!dateIsBetween(row.date,store.preStart,store.preEnd))validationErrors.push(`${prefix}: a data deve estar dentro do período da pré-contagem.`);
    });
    if(store.preStart&&store.preEnd&&store.preStart>store.preEnd)validationErrors.push('A data inicial da pré-contagem deve ser anterior ou igual à data final.');
    if(store.preEnd&&store.inventoryStart&&store.preEnd>store.inventoryStart)validationErrors.push('A pré-contagem deve terminar até o início do inventário.');
  }
  blocks.push(makeBlock('preCount','Pré-contagem',preCountChecks,Boolean(store.preCountEnabled)));

  const dayChecks=[];
  const days=Array.isArray(content.days)?content.days:[];
  addCheck(dayChecks,'Cadastrar ao menos um dia de inventário.',days.length>0);
  const datedDays=days.filter(item=>hasValue(item.date));
  const duplicateDates=datedDays.map(item=>item.date).filter((date,index,list)=>list.indexOf(date)!==index);
  if(duplicateDates.length)validationErrors.push(`Há dias repetidos no planejamento: ${unique(duplicateDates).map(formatDate).join(', ')}.`);
  const orderedDates=datedDays.map(item=>item.date);
  if(orderedDates.some((date,index)=>index>0&&date<orderedDates[index-1]))validationErrors.push('Os dias do inventário devem estar em ordem cronológica.');
  days.forEach((item,dayIndex)=>{
    const prefix=`Dia ${dayIndex+1}`;
    addCheck(dayChecks,`${prefix}: informar data dentro do período do inventário.`,hasValue(item.date)&&dateIsBetween(item.date,store.inventoryStart,store.inventoryEnd));
    addCheck(dayChecks,`${prefix}: informar equipe prevista positiva.`,isPositive(item.headcount));
    addCheck(dayChecks,`${prefix}: cadastrar ao menos uma área ou turno.`,Array.isArray(item.areas)&&item.areas.length>0);
    if(hasValue(item.headcount)&&!isPositive(item.headcount))validationErrors.push(`${prefix}: a equipe prevista deve ser maior que zero.`);
    if(item.date&&store.inventoryStart&&store.inventoryEnd&&!dateIsBetween(item.date,store.inventoryStart,store.inventoryEnd))validationErrors.push(`${prefix}: a data deve estar dentro do período do inventário.`);
    ;(item.areas||[]).forEach((areaItem,areaIndex)=>{
      const areaPrefix=`${prefix}, área ${areaIndex+1}`;
      addCheck(dayChecks,`${areaPrefix}: informar nome.`,hasValue(areaItem.name));
      addCheck(dayChecks,`${areaPrefix}: informar turno.`,hasValue(areaItem.shift));
      addCheck(dayChecks,`${areaPrefix}: informar horário de início.`,hasValue(areaItem.startsAt));
      addCheck(dayChecks,`${areaPrefix}: informar equipe prevista positiva.`,isPositive(areaItem.headcount));
      if(hasValue(areaItem.headcount)&&!isPositive(areaItem.headcount))validationErrors.push(`${areaPrefix}: a equipe prevista deve ser maior que zero.`);
      ;(areaItem.roles||[]).forEach((role,index)=>{
        addCheck(dayChecks,`${areaPrefix}, função ${index+1}: informar função.`,hasValue(role.role));
        addCheck(dayChecks,`${areaPrefix}, função ${index+1}: informar quantidade positiva.`,isPositive(role.count));
        if(hasValue(role.count)&&!isPositive(role.count))validationErrors.push(`${areaPrefix}, função ${index+1}: a quantidade deve ser maior que zero.`);
      });
      ;(areaItem.activities||[]).forEach((activity,index)=>addCheck(dayChecks,`${areaPrefix}, atividade ${index+1}: informar atividade.`,hasValue(activity.name)));
    });
  });
  blocks.push(makeBlock('days','Dias e áreas',dayChecks));

  Object.entries(checklistLabels).forEach(([key,label])=>{
    const items=content.checklists?.[key]||[];
    const checks=[];
    addCheck(checks,`${label}: manter ao menos um item.`,items.length>0);
    items.forEach((item,index)=>{
      addCheck(checks,`${label}, item ${index+1}: preencher a descrição.`,hasValue(item.label));
      addCheck(checks,`${label}, item ${index+1}: concluir o item.`,hasValue(item.label)&&item.done);
    });
    blocks.push(makeBlock(`checklist-${key}`,`Checklist — ${label}`,checks));
  });

  const applicableBlocks=blocks.filter(block=>block.applicable);
  const allChecks=applicableBlocks.flatMap(block=>block.checks);
  const completedChecks=allChecks.filter(check=>check.ok).length;
  let percentage=allChecks.length?Math.floor(completedChecks/allChecks.length*100):0;
  const pendingBlocks=applicableBlocks.filter(block=>block.issues.length>0);
  const approvalIssues=unique([...pendingBlocks.flatMap(block=>block.issues),...validationErrors]);
  if(approvalIssues.length&&percentage===100)percentage=99;
  return {percentage,blocks,pendingBlocks,validationErrors:unique(validationErrors),approvalIssues,approvalReady:approvalIssues.length===0};
}

function formatDate(value){if(!value)return '';const [year,month,date]=value.split('-').map(Number);return new Date(year,month-1,date).toLocaleDateString('pt-BR')}
function formatWeekday(value){if(!value)return 'Data não informada';const [year,month,date]=value.split('-').map(Number);const weekday=new Date(year,month-1,date).toLocaleDateString('pt-BR',{weekday:'long'});return weekday.charAt(0).toUpperCase()+weekday.slice(1)}
function inclusiveDates(start,end){const [startYear,startMonth,startDay]=start.split('-').map(Number);const [endYear,endMonth,endDay]=end.split('-').map(Number);const current=new Date(startYear,startMonth-1,startDay);const limit=new Date(endYear,endMonth-1,endDay);const dates=[];while(current<=limit){const year=current.getFullYear();const month=String(current.getMonth()+1).padStart(2,'0');const date=String(current.getDate()).padStart(2,'0');dates.push(`${year}-${month}-${date}`);current.setDate(current.getDate()+1)}return dates}
function confirmFilledRemoval(item,label,isFilled=hasRowData){return !isFilled(item)||window.confirm(`Excluir ${label}? Os dados preenchidos nesta seção serão perdidos.`)}

export default function PlanningEditor({projects,user,edit,canDimension=false,canApproveTi=false,canApprove=false,catalogs={},onSaved}){
  const [selected,setSelected]=useState('');
  const [content,setContent]=useState(initial());
  const [saving,setSaving]=useState(false);
  const [notice,setNotice]=useState('');
  const project=projects.find(item=>item.id===selected);
  const approvalStageReady=Boolean(project&&['planning','awaiting_dates'].includes(project.status));
  const audit=useMemo(()=>auditPlanning(content),[content]);
  const selectProject=id=>{setSelected(id);requestAnimationFrame(()=>document.getElementById('planning-editor')?.scrollIntoView({behavior:'smooth',block:'start'}))};
  const scrollToAuditBlock=key=>{const target=document.getElementById(key);if(!target)return;target.scrollIntoView({behavior:'smooth',block:'start'});window.setTimeout(()=>target.querySelector('input,textarea,select,button')?.focus({preventScroll:true}),300)};
  const blockAudit=key=>key==='checklists'?audit.blocks.filter(block=>block.key.startsWith('checklist-')).flatMap(block=>block.issues):audit.blocks.find(block=>block.key===key)?.issues||[];
  const isBlockDone=key=>Boolean(content.completedBlocks?.[key]);
  const toggleBlock=key=>{const done=isBlockDone(key);if(!done){const issues=blockAudit(key);if(issues.length){setNotice(`Resolva ${issues.length} pendência(s) antes de concluir este bloco.`);return}}set(['completedBlocks',key],!done)};

  useEffect(()=>{if(project){const saved=project.planning?.content;const next=merge(saved);if(!saved&&Array.isArray(catalogs.checklists)){const templateFor=type=>catalogs.checklists.find(template=>template.checklist_type===type)?.checklist_template_items?.sort((a,b)=>(a.sort_order||0)-(b.sort_order||0)).map(item=>({id:uid(),label:item.label,done:false,required:item.required!==false}))||null;const pre=templateFor('pre_inventory_visit');const planning=templateFor('planning');if(pre?.length)next.checklists.preInventory=pre;if(planning?.length)next.checklists.planning=planning}setContent(next);setNotice('')}},[project,catalogs]);

  const set=(path,value)=>setContent(current=>{const next=structuredClone(current);let target=next;path.slice(0,-1).forEach(key=>target=target[key]);target[path.at(-1)]=value;return next});
  const add=(path,item)=>setContent(current=>{const next=structuredClone(current);let target=next;path.forEach(key=>target=target[key]);target.push(item);return next});
  const remove=(path,index)=>setContent(current=>{const next=structuredClone(current);let target=next;path.forEach(key=>target=target[key]);target.splice(index,1);return next});
  const row=(path,index,key,value)=>setContent(current=>{const next=structuredClone(current);let target=next;path.forEach(pathKey=>target=target[pathKey]);target[index][key]=value;return next});

  function generateDays(){
    const {inventoryStart,inventoryEnd}=content.store;
    if(!inventoryStart||!inventoryEnd){setNotice('Informe o início e o fim do inventário antes de gerar os dias.');return}
    if(inventoryStart>inventoryEnd){setNotice('Corrija a ordem das datas do inventário antes de gerar os dias.');return}
    const startDate=new Date(`${inventoryStart}T12:00:00`);
    const endDate=new Date(`${inventoryEnd}T12:00:00`);
    const totalDays=Math.floor((endDate-startDate)/86400000)+1;
    if(!Number.isFinite(totalDays)||totalDays<1){setNotice('O período informado é inválido. Revise as datas.');return}
    if(totalDays>60){setNotice('O período não pode gerar mais de 60 dias de inventário. Revise as datas.');return}
    const dates=inclusiveDates(inventoryStart,inventoryEnd);
    setContent(current=>{
      const existing=Array.isArray(current.days)?current.days:[];
      const consumed=new Set();
      const generated=dates.map(dateValue=>{
        const match=existing.find(item=>item.date===dateValue&&!consumed.has(item));
        if(match){consumed.add(match);return match}
        return day(dateValue);
      });
      return {...current,days:[...generated,...existing.filter(item=>!consumed.has(item))]};
    });
    setNotice(`${dates.length} dia(s) do período foram gerados ou mesclados sem apagar dados existentes.`);
  }

  async function save(approve=false){
    if(!project)return;
    if(approve&&!canApprove){setNotice('A aprovação é restrita a administradores, supervisores e gestores operacionais.');return}
    if(approve&&!approvalStageReady){setNotice('Este projeto ainda não está em uma etapa elegível para aprovação.');return}
    if(approve&&!audit.approvalReady){
      const preview=audit.approvalIssues.slice(0,3).join(' ');
      const remaining=audit.approvalIssues.length-3;
      setNotice(`Não foi possível aprovar. ${preview}${remaining>0?` E mais ${remaining} pendência(s).`:''}`);
      return;
    }
    setSaving(true);
    try{
      if(approve){
        const {error}=await supabase.rpc('approve_planning',{p_project_id:project.id,p_content:content,p_completion_percentage:audit.percentage});
        if(error)throw error;
      }else{
        const payload={project_id:project.id,content,completion_percentage:audit.percentage,status:'in_progress',updated_at:new Date().toISOString()};
        const startedBy=project.planning?.started_by||user?.id;
        if(startedBy)payload.started_by=startedBy;
        const {error}=await supabase.from('plannings').upsert(payload,{onConflict:'project_id'});
        if(error)throw error;
      }
      if(approve)setNotice('Planejamento aprovado de forma segura e transacional.');
      else if(audit.validationErrors.length)setNotice(`Rascunho salvo com aviso: ${audit.validationErrors.length} inconsistência(s) de datas ou quantidades e ${audit.approvalIssues.length} pendência(s) no total.`);
      else if(audit.approvalIssues.length)setNotice(`Rascunho salvo com ${audit.approvalIssues.length} pendência(s).`);
      else setNotice('Rascunho salvo e pronto para aprovação.');
      await onSaved?.();
    }catch(error){setNotice(error.message)}finally{setSaving(false)}
  }

  const exportRows=()=>{const rows=[['PLANEJAMENTO DE INVENTÁRIO'],['Cliente',project.company_name||''],['Referência',project.reference||''],['Status',project.status||''],['Progresso',`${audit.percentage}%`],['Unidade',content.store?.unit||''],['Período do inventário',`${content.store?.inventoryStart||''} a ${content.store?.inventoryEnd||''}`],['Efetivo geral',content.store?.headcount||'']];const push=(title,headers,items,mapper)=>{rows.push([], [title], headers);(items||[]).forEach(item=>rows.push(mapper(item)))};push('Responsáveis',['Função','Responsável','Observação'],content.responsibilities,item=>[item.role||'',item.person||'',item.notes||'']);push('Transportes',['Data','Horário','Trajeto','Passageiros','Quantidade','Observação'],content.logistics?.transports,item=>[item.date||'',item.time||'',item.route||'',item.passengers||'',item.quantity||'',item.notes||'']);push('Hospedagens',['Hóspedes','Quartos','Entrada','Saída','Quantidade','Observação'],content.logistics?.accommodations,item=>[item.guests||'',item.rooms||'',item.checkIn||'',item.checkOut||'',item.count||'',item.notes||'']);push('Equipamentos do cliente',['Equipamento','Data','Turno','Quantidade','Status','Observação'],content.clientEquipment?.rows,item=>[item.equipment||'',item.date||'',item.shift||'',item.quantity||'',item.status||'',item.notes||'']);push('Equipamentos Contagem',['Equipamento','Data','Turno','Quantidade','Status','Observação'],content.contagemEquipment?.rows,item=>[item.equipment||'',item.date||'',item.shift||'',item.quantity||'',item.status||'',item.notes||'']);push('Pré-contagem',['Data','Horário','Equipe','Quantidade','Observação'],content.preCount?.rows,item=>[item.date||'',item.time||'',item.team||'',item.count||'',item.notes||'']);rows.push([],['Dias e áreas'],['Dia','Área','Turno','Início','Equipe','Função','Qtd. função','Nomes','Atividade','Observação']);(content.days||[]).forEach((dayItem,index)=>(dayItem.areas||[]).forEach(areaItem=>{const roles=areaItem.roles?.length?areaItem.roles:[{}];const activities=areaItem.activities?.length?areaItem.activities:[{}];const total=Math.max(roles.length,activities.length);for(let i=0;i<total;i+=1){const role=roles[i]||{},activity=activities[i]||{};rows.push([dayItem.date||`Dia ${index+1}`,areaItem.name||'',areaItem.shift||'',areaItem.startsAt||'',areaItem.headcount||'',role.role||'',role.count||'',role.names||'',activity.name||'',activity.notes||''])}}));Object.entries(content.checklists||{}).forEach(([key,items])=>push(`Checklist ${key}`,['Item','Concluído','Concluído em'],items,item=>[item.label||'',item.done?'Sim':'Não',item.completedAt||'']));return rows};
  const exportFilename=()=>`planejamento-${(project.company_name||'inventario').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/gi,'-').replace(/^-|-$/g,'').toLowerCase()||'inventario'}`;
  function exportExcel(){const sheet=XLSX.utils.aoa_to_sheet(exportRows());sheet['!cols']=[{wch:28},{wch:28},{wch:24},{wch:18},{wch:18},{wch:24},{wch:18},{wch:24},{wch:32},{wch:32}];const workbook=XLSX.utils.book_new();XLSX.utils.book_append_sheet(workbook,sheet,'Planejamento');XLSX.writeFile(workbook,`${exportFilename()}.xlsx`);setNotice('Excel exportado com sucesso.')}
  function exportPdf(){const doc=new jsPDF({unit:'pt',format:'a4'});const rows=exportRows();let y=42;rows.forEach((row,index)=>{const text=row.filter(value=>value!==null&&value!==undefined&&String(value)!=='').join('  |  ');if(!text){y+=8;return}const lines=doc.splitTextToSize(text,515);if(y+lines.length*13>800){doc.addPage();y=42}doc.setFont('helvetica',index===0?'bold':'normal');doc.setFontSize(index===0?15:9);doc.setTextColor(index===0?'#242323':'#4f5661');doc.text(lines,40,y);y+=lines.length*13+4});doc.save(`${exportFilename()}.pdf`);setNotice('PDF exportado com sucesso.')}
  return <section className="planning-shell">
    <PlanningKanban projects={projects} onSelect={selectProject} edit={edit} canDimension={canDimension} canApproveTi={canApproveTi}/>
    <div className="card planning-header" id="planning-editor">
      <div><h2>Planejamento por blocos</h2><p>Preencha no seu ritmo. O progresso fica salvo e a aprovação exige todos os blocos aplicáveis e os três checklists concluídos.</p></div>
      <div className="planning-tools"><select value={selected} onChange={event=>setSelected(event.target.value)}><option value="">Selecione uma solicitação</option>{projects.map(item=><option key={item.id} value={item.id}>{item.company_name} · {item.reference}</option>)}</select>{project&&<div className="export-actions"><button type="button" onClick={exportPdf}>Exportar PDF</button><button type="button" onClick={exportExcel}>Exportar Excel</button></div>}</div>
    </div>
    {!project?<div className="card"><p>Crie ou selecione uma solicitação para começar o planejamento.</p></div>:<>
      <div className="card progress-card">
        <div className="progress-heading"><div><b>{project.company_name}</b><small>{project.reference}</small></div><b>{audit.percentage}% concluído</b></div>
        <div className="progress" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow={audit.percentage}><i style={{width:`${audit.percentage}%`}}/></div>
        <AuditSummary audit={audit} onNavigate={scrollToAuditBlock}/>
      </div>
      <Block blockKey="store" completed={isBlockDone('store')} onToggle={()=>toggleBlock('store')} title="1. Informações da loja" subtitle="Períodos e efetivo geral">
        <div className="grid"><Input label="Unidade" value={content.store.unit} onChange={value=>set(['store','unit'],value)}/><Input label="Efetivo geral previsto" type="number" value={content.store.headcount} onChange={value=>set(['store','headcount'],value)}/><Toggle label="Possui pré-contagem" checked={content.store.preCountEnabled} onChange={value=>set(['store','preCountEnabled'],value)}/>{content.store.preCountEnabled&&<><Input label="Início pré-contagem" type="date" value={content.store.preStart} onChange={value=>set(['store','preStart'],value)}/><Input label="Fim pré-contagem" type="date" value={content.store.preEnd} onChange={value=>set(['store','preEnd'],value)}/></>}<Input label="Início do inventário" type="date" value={content.store.inventoryStart} onChange={value=>set(['store','inventoryStart'],value)}/><Input label="Fim do inventário" type="date" value={content.store.inventoryEnd} onChange={value=>set(['store','inventoryEnd'],value)}/></div>
      </Block>
      <Block blockKey="responsibilities" completed={isBlockDone('responsibilities')} onToggle={()=>toggleBlock('responsibilities')} title="2. Responsáveis pela operação" subtitle="Funções configuráveis e responsáveis">
        <Rows rows={content.responsibilities} add={()=>add(['responsibilities'],{id:uid(),role:'',person:'',notes:''})} remove={index=>remove(['responsibilities'],index)}>{(item,index)=><div className="row-grid"><Input label="Função" list="roles" value={item.role} onChange={value=>row(['responsibilities'],index,'role',value)}/><Input label="Responsável" value={item.person} onChange={value=>row(['responsibilities'],index,'person',value)}/><Input label="Observação" value={item.notes} onChange={value=>row(['responsibilities'],index,'notes',value)}/></div>}</Rows>
      </Block>
      <Block blockKey="logistics" completed={isBlockDone('logistics')} onToggle={()=>toggleBlock('logistics')} title="3. Logística" subtitle="Transporte, hospedagem e orientações">
        <h3>Transporte</h3>
        <Rows rows={content.logistics.transports} add={()=>add(['logistics','transports'],{id:uid(),date:'',time:'',route:'',passengers:'',quantity:'',notes:''})} remove={index=>remove(['logistics','transports'],index)}>{(item,index)=><div className="row-grid four"><Input label="Data" type="date" value={item.date} onChange={value=>row(['logistics','transports'],index,'date',value)}/><Input label="Horário" type="time" value={item.time} onChange={value=>row(['logistics','transports'],index,'time',value)}/><Input label="Trajeto" value={item.route} onChange={value=>row(['logistics','transports'],index,'route',value)}/><Input label="Passageiros" value={item.passengers} onChange={value=>row(['logistics','transports'],index,'passengers',value)}/><Input label="Qtd." type="number" value={item.quantity} onChange={value=>row(['logistics','transports'],index,'quantity',value)}/><Input label="Observação" value={item.notes} onChange={value=>row(['logistics','transports'],index,'notes',value)}/></div>}</Rows>
        <h3>Hospedagem</h3>
        <Rows rows={content.logistics.accommodations} add={()=>add(['logistics','accommodations'],{id:uid(),guests:'',rooms:'',checkIn:'',checkOut:'',count:'',notes:''})} remove={index=>remove(['logistics','accommodations'],index)}>{(item,index)=><div className="row-grid four"><Input label="Hóspedes" value={item.guests} onChange={value=>row(['logistics','accommodations'],index,'guests',value)}/><Input label="Quartos" value={item.rooms} onChange={value=>row(['logistics','accommodations'],index,'rooms',value)}/><Input label="Entrada" type="date" value={item.checkIn} onChange={value=>row(['logistics','accommodations'],index,'checkIn',value)}/><Input label="Saída" type="date" value={item.checkOut} onChange={value=>row(['logistics','accommodations'],index,'checkOut',value)}/><Input label="Qtd. hóspedes" type="number" value={item.count} onChange={value=>row(['logistics','accommodations'],index,'count',value)}/><Input label="Observação" value={item.notes} onChange={value=>row(['logistics','accommodations'],index,'notes',value)}/></div>}</Rows>
        <Text label="Observações gerais de logística" value={content.logistics.notes} onChange={value=>set(['logistics','notes'],value)}/>
      </Block>
      <Equipment blockKey="clientEquipment" completed={isBlockDone('clientEquipment')} onToggle={()=>toggleBlock('clientEquipment')} title="4. Equipamentos do cliente" value={content.clientEquipment} path="clientEquipment" setContent={setContent}/>
      <Equipment blockKey="contagemEquipment" completed={isBlockDone('contagemEquipment')} onToggle={()=>toggleBlock('contagemEquipment')} title="5. Equipamentos Contagem" value={content.contagemEquipment} path="contagemEquipment" setContent={setContent}/>
      <Block blockKey="preCount" completed={isBlockDone('preCount')} onToggle={()=>toggleBlock('preCount')} title="6. Pré-contagem" subtitle="Datas, horários, equipe e efetivo">
        {!content.store.preCountEnabled&&<p className="block-hint">Ative “Possui pré-contagem” nas informações da loja para tornar este bloco obrigatório.</p>}
        <Rows rows={content.preCount.rows} add={()=>add(['preCount','rows'],{id:uid(),date:'',time:'',team:'',count:'',notes:''})} remove={index=>remove(['preCount','rows'],index)}>{(item,index)=><div className="row-grid four"><Input label="Data" type="date" value={item.date} onChange={value=>row(['preCount','rows'],index,'date',value)}/><Input label="Horário" type="time" value={item.time} onChange={value=>row(['preCount','rows'],index,'time',value)}/><Input label="Equipe" value={item.team} onChange={value=>row(['preCount','rows'],index,'team',value)}/><Input label="Qtd. pessoas" type="number" value={item.count} onChange={value=>row(['preCount','rows'],index,'count',value)}/><Input label="Observação" value={item.notes} onChange={value=>row(['preCount','rows'],index,'notes',value)}/></div>}</Rows>
        <Text label="Detalhes da pré-contagem" value={content.preCount.notes} onChange={value=>set(['preCount','notes'],value)}/>
      </Block>
      <Block blockKey="days" completed={isBlockDone('days')} onToggle={()=>toggleBlock('days')} title="7. Dias, turnos e áreas do inventário" subtitle="Adicione quantos dias e sub-blocos forem necessários">
        <div className="day-actions"><button onClick={()=>add(['days'],day())}>+ Adicionar dia</button><button onClick={generateDays}>Gerar dias do período</button></div>
        {content.days.map((item,index)=><DayEditor key={item.id||index} day={item} index={index} setContent={setContent} removeDay={()=>remove(['days'],index)}/>) }
      </Block>
      <Block blockKey="checklists" completed={isBlockDone('checklists')} onToggle={()=>toggleBlock('checklists')} title="8. Checklists" subtitle="Edite os itens conforme a lista final da Contagem; os três checklists precisam estar preenchidos e concluídos para aprovação.">
        <Checklist anchorId="checklist-preInventory" title="Checklist Visita Pré-Inventário" deadline={content.store.inventoryStart} subtitle="Realizar até um dia antes do inventário; recomendado com três dias de antecedência." items={content.checklists.preInventory} userId={user?.id} onChange={items=>set(['checklists','preInventory'],items)}/>
        <Checklist anchorId="checklist-planning" title="Checklist de planejamento" subtitle="Itens operacionais que serão definidos e refinados pela Contagem." items={content.checklists.planning} userId={user?.id} onChange={items=>set(['checklists','planning'],items)}/>
        <Checklist anchorId="checklist-final" title="Checklist final de aprovação" subtitle="Obrigatório para concluir e aprovar o planejamento." items={content.checklists.final} userId={user?.id} onChange={items=>set(['checklists','final'],items)}/>
      </Block>
      <div className="sticky-actions"><span>{notice||(!canApprove?'A aprovação é restrita a administradores, supervisores e gestores operacionais.':!approvalStageReady?'Este projeto ainda não está em uma etapa elegível para aprovação.':'')}</span><button onClick={()=>save(false)} disabled={saving}>{saving?'Salvando…':'Salvar rascunho'}</button><button className="primary" onClick={()=>save(true)} disabled={saving||!canApprove||!approvalStageReady} title={!canApprove?'Seu perfil não possui permissão para aprovar.':!approvalStageReady?'Projeto fora da etapa de aprovação.':''}>Aprovar planejamento</button></div>
    </>}
  </section>
}

function PlanningKanban({projects,onSelect,edit,canDimension=false,canApproveTi=false}){const [search,setSearch]=useState('');const [dates,setDates]=useState({});const normalizedSearch=search.trim().toLocaleLowerCase('pt-BR');const active=projects.filter(item=>item.status!=='cancelled');const filtered=normalizedSearch?active.filter(item=>[item.company_name,item.trade_name,item.cnpj,item.reference,item.inventory_type].filter(Boolean).some(value=>String(value).toLocaleLowerCase('pt-BR').includes(normalizedSearch))):active;function updateDate(id,key,value){setDates(current=>({...current,[id]:{...current[id],[key]:value}}))}function saveVisitOptions(id){const values=dates[id]||{};if(!values.a||!values.b)return alert('Informe duas opções de data e horário para a visita de dimensionamento.');edit?.(id,{date_options:[values.a,values.b]},'Duas opções de visita de dimensionamento registradas no Planejamento')}function action(id,patch,message){edit?.(id,patch,message)}return <section className="planning-kanban"><div className="kanban-heading"><div><span className="eyebrow">Fluxo único operacional</span><h2>Inventários em movimento</h2><p>Entrada, dimensionamento, TI, planejamento e conclusão no mesmo Kanban. Clique em um cartão para abrir os detalhes.</p><div className="kanban-search"><input aria-label="Pesquisar inventários" value={search} onChange={event=>setSearch(event.target.value)} placeholder="Pesquisar empresa, CNPJ ou referência"/>{search&&<button type="button" onClick={()=>setSearch('')}>Limpar</button>}</div></div><span className="kanban-total">{filtered.length} {filtered.length===1?'inventário':'inventários'}</span></div><div className="kanban-board">{planningColumns.map(column=>{const items=filtered.filter(item=>column.statuses.includes(item.status));return <div className={`kanban-column kanban-column-${column.key}`} key={column.key}><div className="kanban-column-head"><div><span className="kanban-dot"/><b>{column.label}</b></div><span>{items.length}</span></div><div className="kanban-cards">{items.length?items.map(item=>{const content=item.planning?.content||{};const audit=auditPlanning(content);const store=content.store||{};const datesLabel=store.inventoryStart&&store.inventoryEnd?`${formatDate(store.inventoryStart)} – ${formatDate(store.inventoryEnd)}`:'Período não definido';const pending=item.planning?audit.approvalIssues.length:null;const optionState=dates[item.id]||{};return <article className="kanban-card" key={item.id} onClick={()=>onSelect(item.id)}><div className="kanban-card-top"><span className="kanban-reference">{item.reference||'Sem referência'}</span><span className={`kanban-status kanban-status-${item.status}`}>{planningStatus[item.status]||item.status}</span></div><h3>{item.company_name||'Cliente sem cadastro'}</h3><p className="kanban-meta">{store.unit||item.inventory_type||'Unidade não definida'}</p><div className="kanban-card-info"><span><b>Período</b>{datesLabel}</span><span><b>Dias</b>{content.days?.length||0}</span></div><div className="kanban-progress-line"><i style={{width:`${audit.percentage}%`}}/></div><div className="kanban-card-bottom"><span>{item.planning?`${audit.percentage}% preenchido`:'Planejamento será iniciado após o gate'}</span>{pending===null?<span className="kanban-pending neutral">Ação necessária</span>:pending>0?<span className="kanban-pending">{pending} pendência(s)</span>:<span className="kanban-pending ready">Pronto</span>}</div><div className="kanban-card-actions" onClick={event=>event.stopPropagation()}>{item.status==='received'&&<button type="button" disabled={!canDimension} title={!canDimension?'Seu perfil não pode iniciar dimensionamentos.':''} onClick={()=>action(item.id,{status:'awaiting_dimensioning'},'Dimensionamento iniciado no Planejamento')}>Iniciar dimensionamento</button>}{item.status==='awaiting_dimensioning'&&<><div className="kanban-datebox"><input aria-label="Primeira opção de data da visita" type="datetime-local" value={optionState.a||''} onChange={event=>updateDate(item.id,'a',event.target.value)}/><input aria-label="Segunda opção de data da visita" type="datetime-local" value={optionState.b||''} onChange={event=>updateDate(item.id,'b',event.target.value)}/><button type="button" onClick={()=>saveVisitOptions(item.id)}>Salvar opções da visita</button></div><button type="button" disabled={!canDimension} title={!canDimension?'Seu perfil não pode concluir dimensionamentos.':''} onClick={()=>action(item.id,{status:'awaiting_ti'},'Dimensionamento concluído; encaminhado para TI')}>Concluir dimensionamento</button></>}{item.status==='awaiting_ti'&&<button type="button" disabled={!canApproveTi} title={!canApproveTi?'Seu perfil não pode validar TI.':''} onClick={()=>action(item.id,{status:'planning'},'TI aprovou layout e sistema; planejamento liberado')}>Validar TI e liberar planejamento</button>}{item.status==='awaiting_dates'&&<><span className="kanban-legacy-note">Datas já registradas. Abra o cartão para revisar o planejamento.</span><button type="button" onClick={()=>onSelect(item.id)}>Abrir planejamento</button></>}{item.status==='planning'&&<button type="button" onClick={()=>onSelect(item.id)}>Abrir planejamento</button>}{item.status==='confirmed'&&<button type="button" onClick={()=>onSelect(item.id)}>Consultar planejamento</button>}</div></article>}) : <div className="kanban-empty">Nenhum inventário nesta etapa.</div>}</div></div>})}</div></section>}
function AuditSummary({audit,onNavigate}){return <div className={`audit-summary ${audit.approvalReady?'is-ready':'has-pending'}`}><div className="audit-summary-head"><div><h3>{audit.approvalReady?'Planejamento pronto para aprovação':'Pendências por bloco'}</h3><p>{audit.approvalReady?'Todos os blocos aplicáveis e checklists estão completos.':`${audit.approvalIssues.length} pendência(s) precisam de atenção antes da aprovação.`}</p></div>{audit.validationErrors.length>0&&<span className="audit-warning">{audit.validationErrors.length} inconsistência(s)</span>}</div>{audit.pendingBlocks.length>0&&<div className="audit-blocks">{audit.pendingBlocks.map(block=><article key={block.key} className={block.key.startsWith('checklist-')?'audit-block-link':''} role={block.key.startsWith('checklist-')?'button':undefined} tabIndex={block.key.startsWith('checklist-')?0:undefined} onClick={block.key.startsWith('checklist-')?()=>onNavigate?.(block.key):undefined} onKeyDown={block.key.startsWith('checklist-')?event=>{if(event.key==='Enter'||event.key===' ')onNavigate?.(block.key)}:undefined}><div><b>{block.label}</b><span>{block.percentage}%</span></div><ul>{block.issues.slice(0,4).map(issue=><li key={issue}>{issue}</li>)}</ul>{block.issues.length>4&&<small>+ {block.issues.length-4} pendência(s) neste bloco</small>}</article>)}</div>}</div>}
function Block({blockKey,title,subtitle,children,completed=false,onToggle}){const [expanded,setExpanded]=useState(!completed);useEffect(()=>{if(!completed)setExpanded(true)},[completed]);const handleToggle=()=>{onToggle?.();setExpanded(!completed)};return <section className={`card plan-block ${completed?'is-completed':''}`}><div className="plan-block-header"><div className="plan-block-title"><h2>{completed&&<span className="block-check" aria-hidden="true">✓</span>}{title}</h2>{(!completed||expanded)&&subtitle&&<p>{subtitle}</p>}</div><div className="plan-block-controls">{completed&&<span className="block-complete-label">Concluído</span>}<button type="button" className="block-complete-button" onClick={handleToggle}>{completed?'Reabrir bloco':'Concluir bloco'}</button></div></div>{completed&&!expanded?<button type="button" className="block-collapsed-summary" onClick={()=>setExpanded(true)}><span>✓ Bloco concluído</span><span>Expandir para consultar ou editar</span></button>:<div className="plan-block-body">{children}</div>}</section>}
function Input({label,value,onChange,type='text',list,min}){const minimum=type==='number'?(min??1):min;return <label>{label}<input list={list} type={type} min={minimum} value={value??''} onChange={event=>onChange(event.target.value)}/></label>}
function Text({label,value,onChange}){return <label className="text-area">{label}<textarea value={value??''} onChange={event=>onChange(event.target.value)} placeholder="Insira os detalhes necessários…"/></label>}
function Toggle({label,checked,onChange}){return <label className="toggle"><input type="checkbox" checked={checked} onChange={event=>onChange(event.target.checked)}/>{label}</label>}
function Rows({rows,add,remove,children,isFilled=hasRowData}){const removeRow=index=>{if(confirmFilledRemoval(rows[index],'esta linha',isFilled))remove(index)};return <div className="rows">{rows.map((item,index)=><div className="dynamic-row" key={item.id||index}>{children(item,index)}<button className="delete" onClick={()=>removeRow(index)}>Excluir linha</button></div>)}<button onClick={add}>+ Adicionar linha</button></div>}
function Equipment({blockKey,completed,onToggle,title,value,path,setContent}){const add=()=>setContent(current=>{const next=structuredClone(current);next[path].rows.push({id:uid(),equipment:'',date:'',shift:'',quantity:'',status:'Solicitado',notes:''});return next});const remove=index=>setContent(current=>{const next=structuredClone(current);next[path].rows.splice(index,1);return next});const row=(index,key,value)=>setContent(current=>{const next=structuredClone(current);next[path].rows[index][key]=value;return next});const notes=value=>setContent(current=>{const next=structuredClone(current);next[path].notes=value;return next});return <Block blockKey={blockKey} completed={completed} onToggle={onToggle} title={title} subtitle="Por item, dia e turno"><Rows rows={value.rows} add={add} remove={remove}>{(item,index)=><div className="row-grid four"><Input label="Equipamento" list="equipment" value={item.equipment} onChange={next=>row(index,'equipment',next)}/><Input label="Dia" type="date" value={item.date} onChange={next=>row(index,'date',next)}/><Input label="Turno" value={item.shift} onChange={next=>row(index,'shift',next)}/><Input label="Quantidade" type="number" value={item.quantity} onChange={next=>row(index,'quantity',next)}/><Input label="Status" value={item.status} onChange={next=>row(index,'status',next)}/><Input label="Observação" value={item.notes} onChange={next=>row(index,'notes',next)}/></div>}</Rows><Text label="Detalhes do bloco" value={value.notes} onChange={notes}/></Block>}
function DayEditor({day:dayItem,index,setContent,removeDay}){const setDay=(key,value)=>setContent(current=>{const next=structuredClone(current);next.days[index][key]=value;return next});const addArea=kind=>setContent(current=>{const next=structuredClone(current);next.days[index].areas.push(area(kind));return next});const confirmRemove=()=>{if(confirmFilledRemoval(dayItem,'este dia',item=>hasRowData(item)))removeDay()};return <div className="day-card"><div className="day-head"><div><h3>Dia {index+1}</h3><small>{dayItem.date?`${formatWeekday(dayItem.date)} · ${formatDate(dayItem.date)}`:'Data não informada'}</small></div><button className="delete" onClick={confirmRemove}>Excluir dia</button></div><div className="grid"><Input label="Data" type="date" value={dayItem.date} onChange={value=>setDay('date',value)}/><Input label="Equipe prevista" type="number" value={dayItem.headcount} onChange={value=>setDay('headcount',value)}/></div><Text label="Observações do dia" value={dayItem.notes} onChange={value=>setDay('notes',value)}/>{(dayItem.areas||[]).map((areaItem,areaIndex)=><AreaEditor key={areaItem.id||areaIndex} area={areaItem} dayIndex={index} areaIndex={areaIndex} setContent={setContent}/>) }<div className="area-templates"><button onClick={()=>addArea('Depósito')}>+ Depósito</button><button onClick={()=>addArea('Câmaras')}>+ Câmaras</button><button onClick={()=>addArea('Coordenação')}>+ Coordenação</button><button onClick={()=>addArea('Divisão da equipe')}>+ Divisão da equipe</button><button onClick={()=>addArea('Outro turno / área')}>+ Outro</button></div></div>}
function AreaEditor({area:areaItem,dayIndex,areaIndex,setContent}){const update=(key,value)=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex][key]=value;return next});const addRole=()=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].roles.push({id:uid(),role:'',count:'',names:''});return next});const addAct=()=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].activities.push({id:uid(),name:'',notes:''});return next});const delArea=()=>{if(!confirmFilledRemoval(areaItem,'esta área'))return;setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas.splice(areaIndex,1);return next})};const removeRole=roleIndex=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].roles.splice(roleIndex,1);return next});const removeActivity=activityIndex=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].activities.splice(activityIndex,1);return next});return <div className="area-card"><div className="day-head"><h3>{areaItem.name||'Área / turno'}</h3><button className="delete" onClick={delArea}>Excluir área</button></div><div className="grid"><Input label="Área" value={areaItem.name} onChange={value=>update('name',value)}/><Input label="Turno" value={areaItem.shift} onChange={value=>update('shift',value)}/><Input label="Início" type="time" value={areaItem.startsAt} onChange={value=>update('startsAt',value)}/><Input label="Equipe prevista" type="number" value={areaItem.headcount} onChange={value=>update('headcount',value)}/></div><h4>Equipe</h4><Rows rows={areaItem.roles||[]} add={addRole} remove={removeRole}>{(roleItem,roleIndex)=><div className="row-grid"><Input label="Função" list="roles" value={roleItem.role} onChange={value=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].roles[roleIndex].role=value;return next})}/><Input label="Quantidade" type="number" value={roleItem.count} onChange={value=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].roles[roleIndex].count=value;return next})}/><Input label="Nomes" value={roleItem.names} onChange={value=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].roles[roleIndex].names=value;return next})}/></div>}</Rows><h4>Atividades</h4><Rows rows={areaItem.activities||[]} add={addAct} remove={removeActivity}>{(activity,activityIndex)=><div className="row-grid"><Input label="Atividade" list="activities" value={activity.name} onChange={value=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].activities[activityIndex].name=value;return next})}/><Input label="Observação da atividade" value={activity.notes} onChange={value=>setContent(current=>{const next=structuredClone(current);next.days[dayIndex].areas[areaIndex].activities[activityIndex].notes=value;return next})}/></div>}</Rows><Text label="Detalhes da área" value={areaItem.notes} onChange={value=>update('notes',value)}/></div>}
function Checklist({anchorId,title,subtitle,deadline,items,userId,onChange}){const recommended=deadline?new Date(new Date(`${deadline}T12:00:00`).getTime()-3*86400000).toLocaleDateString('pt-BR'):'';const limit=deadline?new Date(new Date(`${deadline}T12:00:00`).getTime()-86400000).toLocaleDateString('pt-BR'):'';const toggle=(item,index,done)=>onChange(items.map((current,currentIndex)=>{if(currentIndex!==index)return current;if(done)return {...current,done:true,completedAt:new Date().toISOString(),completedBy:userId||null};const {completedAt,completedBy,...reopened}=current;return {...reopened,done:false}}));const removeItem=index=>{const item=items[index];if(!confirmFilledRemoval(item,'este item de checklist',current=>hasValue(current?.label)||current?.done))return;onChange(items.filter((_,currentIndex)=>currentIndex!==index))};return <div id={anchorId} className="checklist"><h3>{title}</h3>{subtitle&&<p>{subtitle}</p>}{deadline&&<small className="check-deadline">{limit?`Prazo: ${limit} · Recomendado: ${recommended}`:'Defina a data do inventário para calcular o prazo.'}</small>}{items.map((item,index)=><div className={`check-item ${item.done?'is-done':''}`} key={item.id||index}><input type="checkbox" checked={Boolean(item.done)} onChange={event=>toggle(item,index,event.target.checked)}/><input aria-label="Item do checklist" value={item.label??''} onChange={event=>onChange(items.map((current,currentIndex)=>currentIndex===index?{...current,label:event.target.value}:current))}/><button className="delete" onClick={()=>removeItem(index)}>Excluir</button></div>)}<button onClick={()=>onChange([...items,{id:uid(),label:'',done:false}])}>+ Adicionar item</button></div>}
export function PlanningLists({catalogs={}}){const roleOptions=catalogs.roles?.length?catalogs.roles:roles;const activityOptions=catalogs.activities?.length?catalogs.activities.map(item=>item.name):activities;const equipmentOptions=catalogs.equipment?.length?catalogs.equipment.map(item=>item.name):equipment;return <><datalist id="roles">{roleOptions.map(item=><option key={item} value={item}/>)}</datalist><datalist id="activities">{activityOptions.map(item=><option key={item} value={item}/>)}</datalist><datalist id="equipment">{equipmentOptions.map(item=><option key={item} value={item}/>)}</datalist></>}
