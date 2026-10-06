# Crea el dashboard "Seguimiento Zafiro" en la cuenta 37, replicando el de desarrollo.
# Idempotente: si ya existe un dashboard con ese nombre, no lo duplica.
require 'json'

# Cuenta y fuente se pasan por entorno para que el script sirva en cualquier instalación:
#   CUENTA=37 FUENTE=7 bundle exec rails runner lib/tasks/jabvox/crear_dashboard_zafiro.rb
CUENTA = (ENV['CUENTA'] || 37).to_i
FUENTE = (ENV['FUENTE'] || 7).to_i

cuenta = Account.find(CUENTA)
fuente = cuenta.jabvox_analytics_data_sources.find(FUENTE)
puts "cuenta: #{cuenta.name} | fuente: #{fuente.name_jabvox} (#{fuente.database_jabvox})"

existente = cuenta.jabvox_analytics_dashboards.find_by(name_jabvox: 'Seguimiento Zafiro')
if existente
  puts "YA EXISTE el dashboard id=#{existente.id} con #{existente.widgets.count} widgets. No se crea otro."
  exit
end

WIDGETS = JSON.parse(<<~'JSON_DATA')
[
  {
    "title": "1. General por canal",
    "type": "table",
    "sql": "SELECT lc.posible_estrategia_zafiro_c AS `CANAL`,\nCOUNT(*) AS `NE`,\nROUND(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2)))) AS `Meta Venta`,\nROUND(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2)))) AS `Meta pedidos`,\nSUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS `Con Pedido`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `Efectividad`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)) AS `VENTA_SIN_IVA`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END),0)) AS `OP`,\nCONCAT(ROUND(100.0*SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2))),0)),'%') AS `Cumplimiento Venta`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2))),0),1),'%') AS `Cumplimiento pedidos`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.posible_estrategia_zafiro_c<>''\nGROUP BY 1 ORDER BY 1",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 0
  },
  {
    "title": "2. General por zona",
    "type": "table",
    "sql": "SELECT lc.zona_c AS `ZONA`,\nCOUNT(*) AS `NE`,\nROUND(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2)))) AS `Meta Venta`,\nROUND(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2)))) AS `Meta pedidos`,\nSUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS `Con Pedido`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `Efectividad`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)) AS `VENTA_SIN_IVA`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END),0)) AS `OP`,\nCONCAT(ROUND(100.0*SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2))),0)),'%') AS `Cumplimiento Venta`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2))),0),1),'%') AS `Cumplimiento pedidos`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.zona_c<>''\nGROUP BY 1 ORDER BY 1",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 1
  },
  {
    "title": "3. Por tipo de Zafiro",
    "type": "table",
    "sql": "SELECT lc.segmento_zafiro_c AS `TIPO`, lc.posible_estrategia_zafiro_c AS `CANAL`, lc.zona_c AS `ZONA`,\nCOUNT(*) AS `NE`,\nROUND(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2)))) AS `Meta Venta`,\nROUND(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2)))) AS `Meta pedidos`,\nSUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS `Con Pedido`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `Efectividad`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)) AS `VENTA_SIN_IVA`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END),0)) AS `OP`,\nCONCAT(ROUND(100.0*SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2))),0)),'%') AS `Cumplimiento Venta`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2))),0),1),'%') AS `Cumplimiento pedidos`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.segmento_zafiro_c<>''\nGROUP BY 1,2,3 ORDER BY 1,2,3",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 2
  },
  {
    "title": "4. Por estrellas",
    "type": "table",
    "sql": "SELECT lc.estrellas_zafiro_c AS `ESTRELLAS`, lc.posible_estrategia_zafiro_c AS `CANAL`, lc.zona_c AS `ZONA`,\nCOUNT(*) AS `NE`,\nROUND(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2)))) AS `Meta Venta`,\nROUND(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2)))) AS `Meta pedidos`,\nSUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS `Con Pedido`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `Efectividad`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)) AS `VENTA_SIN_IVA`,\nROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END),0)) AS `OP`,\nCONCAT(ROUND(100.0*SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)/NULLIF(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2))),0)),'%') AS `Cumplimiento Venta`,\nCONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(SUM(CAST(NULLIF(fc.meta_pedidos_c,'') AS DECIMAL(18,2))),0),1),'%') AS `Cumplimiento pedidos`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.estrellas_zafiro_c<>''\nGROUP BY 1,2,3 ORDER BY 1,2,3",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 3
  },
  {
    "title": "5. Gestion con Liker",
    "type": "table",
    "sql": "SELECT lc.zona_c AS `ZONA`, COUNT(*) AS `NE`,\n       ROUND(SUM(CAST(NULLIF(fc.presupuesto_c,'') AS DECIMAL(18,2)))) AS `Meta Venta`,\n       SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS `Con Pedido`,\n       ROUND(SUM(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2))/1.19)) AS `VENTA_SIN_IVA`,\n       SUM(CASE WHEN lc.gestionado_c='1' THEN 1 ELSE 0 END) AS `GESTIONADOS`,\n       SUM(CASE WHEN lc.contacto_c=1 THEN 1 ELSE 0 END) AS `CONTACTADOS`,\n       CONCAT(ROUND(100.0*SUM(CASE WHEN lc.contacto_c=1 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `CONTACTABILIDAD`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.zona_c<>''\nGROUP BY 1 ORDER BY 1\n",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 4
  },
  {
    "title": "6. Por Mailgroup",
    "type": "table",
    "sql": "SELECT lc.mg_c AS `MG`, COUNT(*) AS `NE`,\n       SUM(CASE WHEN COALESCE(CAST(NULLIF(fc.venta_con_iva_c,'') AS DECIMAL(18,2)),0) <= 0 THEN 1 ELSE 0 END) AS `NE sin Pedido`,\n       SUM(CASE WHEN fc.estado_pedido_c='Cancelado' THEN 1 ELSE 0 END) AS `Cancelados sin pedido`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.mg_c<>''\nGROUP BY 1 ORDER BY 1\n",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 5
  },
  {
    "title": "7. Por Departamento",
    "type": "table",
    "sql": "SELECT lc.nomdepartamento_c AS `DEPARTAMENTO`, COUNT(*) AS `NE`,\n       SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END) AS `NE Con Pedido`,\n       CONCAT(ROUND(100.0*SUM(CASE WHEN CAST(NULLIF(fc.venta_con_iva_c,'0') AS DECIMAL(18,2)) > 0 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `%`\nFROM lk_facturacion_leads_c r\nJOIN lk_facturacion f       ON f.id   = r.lk_facturacion_leadslk_facturacion_idb AND f.deleted = 0\nJOIN lk_facturacion_cstm fc ON fc.id_c = f.id\nJOIN leads_cstm lc          ON lc.id_c = r.lk_facturacion_leadsleads_ida\nWHERE r.deleted = 0 AND f.name = {{CICLO}}\n  AND lc.nomdepartamento_c<>''\nGROUP BY 1 ORDER BY 2 DESC\n",
    "config": {
      "ciclo": "202613",
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 6
  },
  {
    "title": "8. Gestiones por canal y zona",
    "type": "table",
    "sql": "-- Las llamadas del marcador predictivo no quedan enlazadas a un lead, así que no tienen\n-- zona. Se muestran aparte (\"Sin asignar a NE\") en vez de mezclarlas con las zonas\n-- reales, donde su volumen las aplastaría, y en vez de ocultarlas, que escondería\n-- la mitad del esfuerzo del ciclo.\nSELECT CASE WHEN COALESCE(lz.zona_c,'') = '' THEN 'Sin asignar a NE' ELSE lz.zona_c END AS `ZONA`,\n       SUM(CASE WHEN c.direction='Llamada'  THEN 1 ELSE 0 END) AS `Llamadas`,\n       SUM(CASE WHEN c.direction='Whatsapp' THEN 1 ELSE 0 END) AS `WhatsApp`,\n       SUM(CASE WHEN c.direction='Inbound'  THEN 1 ELSE 0 END) AS `Entrantes`,\n       SUM(CASE WHEN c.direction='Outbound' THEN 1 ELSE 0 END) AS `Salientes`,\n       SUM(CASE WHEN c.direction='Asesoria_Grupal' THEN 1 ELSE 0 END) AS `Asesoría grupal`,\n       COUNT(*) AS `Total`\nFROM calls c\nJOIN lk_ciclos ci ON ci.name = {{CICLO}} AND ci.deleted = 0\n                 AND DATE(c.date_entered) BETWEEN ci.inicio AND ci.fin\nLEFT JOIN calls_leads cl ON cl.call_id = c.id AND cl.deleted = 0\nLEFT JOIN leads_cstm lz  ON lz.id_c = cl.lead_id\nWHERE c.deleted = 0\nGROUP BY 1\nORDER BY (`ZONA` = 'Sin asignar a NE'), 1",
    "config": {
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 7
  },
  {
    "title": "9. Resultado de las llamadas",
    "type": "table",
    "sql": "SELECT c.status AS `RESULTADO`,\n       COUNT(*) AS `Gestiones`,\n       CONCAT(ROUND(100.0*COUNT(*)/NULLIF(SUM(COUNT(*)) OVER (),0),1),'%') AS `%`\nFROM calls c\nJOIN lk_ciclos ci ON ci.name = {{CICLO}} AND ci.deleted = 0\n                 AND DATE(c.date_entered) BETWEEN ci.inicio AND ci.fin\nWHERE c.deleted = 0 AND c.status <> ''\nGROUP BY c.status ORDER BY 2 DESC",
    "config": {
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 8
  },
  {
    "title": "10. Tipificación: motivo de contacto",
    "type": "table",
    "sql": "SELECT cs.motivo_contacto_c AS `MOTIVO`,\n       COUNT(*) AS `Gestiones`,\n       CONCAT(ROUND(100.0*COUNT(*)/NULLIF(SUM(COUNT(*)) OVER (),0),1),'%') AS `%`\nFROM calls c\nJOIN calls_cstm cs ON cs.id_c = c.id\nJOIN lk_ciclos ci ON ci.name = {{CICLO}} AND ci.deleted = 0\n                 AND DATE(c.date_entered) BETWEEN ci.inicio AND ci.fin\nWHERE c.deleted = 0 AND cs.motivo_contacto_c IS NOT NULL AND cs.motivo_contacto_c <> ''\nGROUP BY 1 ORDER BY 2 DESC",
    "config": {
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 9
  },
  {
    "title": "11. Tipificación: tipo de servicio",
    "type": "table",
    "sql": "SELECT cs.es_servicio_c AS `SERVICIO`,\n       COUNT(*) AS `Gestiones`,\n       CONCAT(ROUND(100.0*COUNT(*)/NULLIF(SUM(COUNT(*)) OVER (),0),1),'%') AS `%`\nFROM calls c\nJOIN calls_cstm cs ON cs.id_c = c.id\nJOIN lk_ciclos ci ON ci.name = {{CICLO}} AND ci.deleted = 0\n                 AND DATE(c.date_entered) BETWEEN ci.inicio AND ci.fin\nWHERE c.deleted = 0 AND cs.es_servicio_c IS NOT NULL AND cs.es_servicio_c <> ''\nGROUP BY 1 ORDER BY 2 DESC",
    "config": {
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 10
  },
  {
    "title": "12. Productividad por asesor",
    "type": "table",
    "sql": "SELECT COALESCE(NULLIF(u.user_name,''),'(sin asignar)') AS `ASESOR`,\n       COUNT(*) AS `Gestiones`,\n       SUM(CASE WHEN c.direction='Llamada'  THEN 1 ELSE 0 END) AS `Llamadas`,\n       SUM(CASE WHEN c.direction='Whatsapp' THEN 1 ELSE 0 END) AS `WhatsApp`,\n       SUM(CASE WHEN c.status IN ('Buzon_de_voz','No_contesto','Fallo_llamada','Llamada_cortada') THEN 1 ELSE 0 END) AS `Sin contacto`,\n       CONCAT(ROUND(100.0*SUM(CASE WHEN c.status NOT IN ('Buzon_de_voz','No_contesto','Fallo_llamada','Llamada_cortada') THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1),'%') AS `% Efectividad`\nFROM calls c\nJOIN lk_ciclos ci ON ci.name = {{CICLO}} AND ci.deleted = 0\n                 AND DATE(c.date_entered) BETWEEN ci.inicio AND ci.fin\nLEFT JOIN users u ON u.id = c.assigned_user_id\nWHERE c.deleted = 0\nGROUP BY 1 ORDER BY 2 DESC",
    "config": {
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 11
  },
  {
    "title": "13. Contactabilidad por zona",
    "type": "table",
    "sql": "-- Intentos vs. contacto efectivo. \"Contactadas\" cuenta NE distintas con al menos una\n-- gestión que no terminó en buzón/no contesta: una NE llamada diez veces sin éxito no\n-- es contactabilidad.\nSELECT lz.zona_c AS `ZONA`,\n       COUNT(*) AS `Intentos`,\n       COUNT(DISTINCT cl.lead_id) AS `NE gestionadas`,\n       COUNT(DISTINCT CASE WHEN c.status NOT IN ('Buzon_de_voz','No_contesto','Fallo_llamada','Llamada_cortada','No_puede_etender_llamada','Contesta_otra_persona','No_conoce_ne') THEN cl.lead_id END) AS `NE contactadas`,\n       CONCAT(ROUND(100.0*COUNT(DISTINCT CASE WHEN c.status NOT IN ('Buzon_de_voz','No_contesto','Fallo_llamada','Llamada_cortada','No_puede_etender_llamada','Contesta_otra_persona','No_conoce_ne') THEN cl.lead_id END)\n             /NULLIF(COUNT(DISTINCT cl.lead_id),0),1),'%') AS `% Contactabilidad`,\n       ROUND(COUNT(*)/NULLIF(COUNT(DISTINCT cl.lead_id),0),1) AS `Intentos por NE`\nFROM calls c\nJOIN lk_ciclos ci ON ci.name = {{CICLO}} AND ci.deleted = 0\n                 AND DATE(c.date_entered) BETWEEN ci.inicio AND ci.fin\nJOIN calls_leads cl ON cl.call_id = c.id AND cl.deleted = 0\nJOIN leads_cstm lz  ON lz.id_c = cl.lead_id\nWHERE c.deleted = 0 AND lz.zona_c <> ''\nGROUP BY 1 ORDER BY 1",
    "config": {
      "param_sources": {
        "CICLO": {
          "table": "lk_facturacion",
          "column": "name"
        }
      },
      "param_defaults": {
        "CICLO": "202613"
      }
    },
    "position": 12
  }
]
JSON_DATA

dash = cuenta.jabvox_analytics_dashboards.create!(
  name_jabvox: 'Seguimiento Zafiro',
  description_jabvox: 'Replica del seguimiento por ciclo: venta, pedidos, gestion y tipificaciones.',
  layout_jabvox: [], global_filters_jabvox: {},
  created_by_id: cuenta.administrators.first&.id
)
puts "dashboard creado: id=#{dash.id}"

WIDGETS.each do |w|
  dash.widgets.create!(
    account_id: cuenta.id, data_source_id: FUENTE,
    widget_type_jabvox: w['type'], title_jabvox: w['title'],
    custom_sql_jabvox: w['sql'], config_jabvox: w['config'],
    query_spec_jabvox: {}, position_jabvox: w['position']
  )
end
puts "widgets creados: #{dash.widgets.count}"

puts "\n=== verificacion: cada widget responde ==="
dash.widgets.order(:position_jabvox).each do |w|
  out = Jabvox::Analytics::QueryExecutionService.new(data_source: w.data_source)
        .run_custom_sql(w.custom_sql_jabvox, params: { 'CICLO' => '202613' })
  puts format('  %-40s %3d filas', w.title_jabvox[0, 40], out.rows.size)
rescue StandardError => e
  puts "  #{w.title_jabvox}: ERROR #{e.message[0, 90]}"
end
puts "\nURL: /app/accounts/#{CUENTA}/jabvox/analytics/dashboards/#{dash.id}"
