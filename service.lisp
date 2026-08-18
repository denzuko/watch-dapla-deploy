(:repo-name    'watch-dapla-deploy'
 :system-name  'watch-dapla-deploy'
 :fqdn         'watch.dapla.net'
 :vhost-name   'watch'
 :service-user 'invidious'
 :description  'Invidious YouTube frontend'
 :image        'oci.dapla.net/ghcr.io/iv-org/invidious:latest'
 :internal-port 3000
 :health-path  '/'
 :extra-images ('oci.dapla.net/library/postgres:16-alpine')
 :datasets
 (  (:name 'users/invidious'
   :mountpoint '/var/lib/invidious'
   :purpose 'Service account home directory')
  (:name 'containers/invidious'
   :mountpoint '/srv/invidious'
   :purpose 'PostgreSQL data directory'))
)
