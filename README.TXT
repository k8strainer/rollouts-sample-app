# Argo Rollouts mit Prometheus-basiertem AnalysisTemplate und Traffic Weighting # 

Im Folgenden wird kurz und kompakt beschrieben, wie ein Argo Rollout mit AnalysisTemplate auf Basis von Prometheus Metriken 
bei einem Canary Update (mit Traffic Weighting) geprüft werden kann. Zu den Details siehe auch:
https://jhandguy.github.io/posts/smart-canary-deployment/
https://github.com/jhandguy/canary-deployment
Das auf den o. a. Seiten beschrieben Setup wurde an verschiedenen Stellen modifiziert: 
das dort beschriebene Helm-Deployment wurde aus bekannten Gründen nicht verwendet, 
ebenso wurden unter anderem die Ingress-Settings sowie die entsprechenden Settings im AnalysisTemplate angepasst, 
damit es mit einem Operator-gestützten Standard- kube-prometheus-Stack zusammenarbeiten kann. 

_Rollout_
Rollen Sie zunächst die beiden Manifeste im Ordner ../canary-deployment-analysis-prom/ aus:

k apply -f canary-deployment-analysis-prom/

Dadurch wird eine Beispielapplikation ('sample-app') im Namespace 'sample-app' mit den folgenden Komponenten ausgerollt:
1 Argo Rollout (1 Pod) mit 2 vorgeschalteten Services (stable und canary) und Ingress-Ressourcen, 
dazu ein ServiceMonitor (Prometheus) für die App, eine gepatchte Clusterrole für Prometheus 
(damit er den ServiceMonitor erfassen kann), sowie ein AnalysisTemplate dass die 
(über den ServiceMonitor von Prometheus) erfassten Metriken auswertet. 

#Hinweis#
Passen Sie vor dem Rollout die Ingress Ressource ('host: <>') auf Ihre Gegebenheiten an.

Um den Rollout zu überwachen, setzen Sie den folgenden Befehl ab:

k argo rollouts get rollout sample-app --watch -n sample-app

Warten Sie, bis Prometheus den ServiceMonitor für die sample-app erkannt hat. 

# Update und Promote
Führen Sie nun ein Update des Rollouts durch, indem Sie das Image ersetzen:

k argo rollouts set image sample-app \
   sample-app=gcr.io/sci-4-data/sci4/sample-app:latest -n sample-app

Der Rollout pausiert unbeschränkt nach Step 1. Daher promoten Sie den Rollout manuell. 
Achtung: Der AnalysisRun startet erst ab Step 2 (d. h. nach erfolgter Promotion). 

k argo rollouts promote sample-app -n sample-app

# Error erzeugen
Um nun den Rollout während des Updates mit Fehlern zu versorgen die ihn scheitern lassen, 
führen Sie wiederholt im Wechsel einen curl auf die Ingress-IP aus (jeweils mit "/success" und mit "/error" am Ende der URL), z. B.: 

curl 34.147.84.15/success -H "Host: sample-app.<your>.<domain>" -H "X-Canary: always"
curl 34.147.84.15/error -H "Host: sample-app.<your>.<domain>" -H "X-Canary: always"

Die Pausen zwischen den folgenden Rollout Steps nach dem ersten Promote sind per Default auf 3 Minuten eingestellt, 
daher warten Sie etwas. Nach Beendigung des laufenden Steps sollten entsprechende Fehlermeldungen erscheinen, die anzeigen, 
das Probleme aufgetaucht sind und der Rollout abgebrochen wurde:


Name:            sample-app
Namespace:       sample-app
Status:          ✖ Degraded
Message:         RolloutAborted: Rollout aborted update to revision 2: Metric "success-share" assessed Failed due to failed (1) > failureLimit (0)
Strategy:        Canary
  Step:          0/6
  SetWeight:     0
  ActualWeight:  0
Images:          gcr.io/sci-4-data/sci4/sample-app:1.0.0 (stable)
Replicas:
  Desired:       1
  Current:       1
  Updated:       0
  Ready:         1
  Available:     1
NAME                                    KIND         STATUS        AGE    INFO
⟳ sample-app                            Rollout      ✖ Degraded    9m14s
├──# revision:2
│  ├──⧉ sample-app-db6fdcb6             ReplicaSet   • ScaledDown  3m36s  canary,delay:passed
│  └──α sample-app-db6fdcb6-2           AnalysisRun  ✖ Failed      3m30s  ✔ 1,✖ 1
└──# revision:1
   └──⧉ sample-app-66946fbf74           ReplicaSet   ✔ Healthy     8m54s  stable
      └──□ sample-app-66946fbf74-fv8kl  Pod          ✔ Running     8m54s  ready:1/1

Alternativ können Sie auch den Rollout Status abfragen:

k argo rollouts status sample-app -n sample-app
Output:
"Degraded - RolloutAborted: Rollout aborted update to revision 2: Metric "success-share" assessed Failed due to failed (1) > failureLimit (0)
Error: The rollout is in a degraded state with message: RolloutAborted: Rollout aborted update to revision 2: Metric "success-share" 
assessed Failed due to failed"


# Lastverteilung bei einer intakten Canary Rollout Promotion beobachten
Um die Traffic-Verteilung / das Weighting während eines intakten Canary Upgrades zu verfolgen,
führen Sie die folgenden Befehle während der jeweiligen Steps aus (Canary-Weight z, B. 50, 75, 100). 
Führen Sie dazu einfach vor dem neuen Rollout einen undo und einen anschließenden erneuten Promote aus:

k argo rollouts undo sample-app -n sample-app
k argo rollouts promote sample-app -n sample-app

Nun die Prüfung währen der jeweiligen Steps:

for i in {1..1000}; do curl -s sample-app.gke1.itconcepts.cloud/success -H "Host: sample-app.gke1.itconcepts.cloud"; done | sort | uniq -c
    495 {"node":"gke-cluster-01-default-pool-3ff785ee-m3rb","namespace":"sample-app","pod":"sample-app-66946fbf74-chn26","deployment":"stable"}
    505 {"node":"gke-cluster-01-default-pool-51acaa42-4d81","namespace":"sample-app","pod":"sample-app-5fcfc474bd-trgrr","deployment":"canary"}
for i in {1..1000}; do curl -s sample-app.gke1.itconcepts.cloud/success -H "Host: sample-app.gke1.itconcepts.cloud"; done | sort | uniq -c
    255 {"node":"gke-cluster-01-default-pool-3ff785ee-m3rb","namespace":"sample-app","pod":"sample-app-66946fbf74-chn26","deployment":"stable"}
    745 {"node":"gke-cluster-01-default-pool-51acaa42-4d81","namespace":"sample-app","pod":"sample-app-5fcfc474bd-trgrr","deployment":"canary"}
for i in {1..1000}; do curl -s sample-app.gke1.itconcepts.cloud/success -H "Host: sample-app.gke1.itconcepts.cloud"; done | sort | uniq -c
   1000 {"node":"gke-cluster-01-default-pool-51acaa42-4d81","namespace":"sample-app","pod":"sample-app-5fcfc474bd-trgrr","deployment":"canary"}

Die kleinen Ungenauigkeiten, zu sehen oben z. B. bei der 50/50 und 25/75 Verteilung, liegen im nginx-Ingress Controller, 
siehe dazu auch https://github.com/kubernetes/ingress-nginx/issues/9745
Eine Lösung stand im betrachteten Stand noch aus.

