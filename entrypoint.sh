#!/bin/sh

CONSOLE="execute_console_command"

# services activated for this docker container instance will be added to this string
ENABLED_SERVICES=""


source /data/bin/functions.sh
[ -e "$SHOP/docker/build.conf" ] && source $SHOP/docker/build.conf

# abort on first error
set -e

cd $SHOP


# force setting a symlink from sites-available to sites-enabled if vhost file exists
enable_nginx_vhost() {
  NGINX_SITES_AVAILABLE='/etc/nginx/sites-available'
  NGINX_SITES_ENABLED='/etc/nginx/conf.d'
  VHOST=$1
  
  if [ ! -e $NGINX_SITES_AVAILABLE/$VHOST ]; then
    errorText "\t nginx vhost '$VHOST' not found! Can't enable vhost!"
    return
  fi
  
  ln -fs $NGINX_SITES_AVAILABLE/$VHOST $NGINX_SITES_ENABLED/${VHOST}.conf
}


# force setting a symlink from php-fpm/apps-available to php-fpm/pool.d if app file exists
enable_phpfpm_app() {
  FPM_APPS_AVAILABLE="/etc/php/apps"
  FPM_APPS_ENABLED="/usr/local/etc/php-fpm.d"
  
  APP="${1}.conf"
  if [ ! -e $FPM_APPS_AVAILABLE/$APP ]; then
    errorText "\t php-fpm app '$APP' not found! Can't enable app!"
    return
  fi
  
  # enable php-fpm pool config
  ln -fs $FPM_APPS_AVAILABLE/$APP $FPM_APPS_ENABLED/$APP
}


enable_services() {
  for SERVICE in $ENABLED_SERVICES; do
    labelText "Enable ${SERVICE} vHost and PHP-FPM app..."
    
    infoText "Enbable ${SERVICE} - Link nginx vHost to sites-enabled/..."
    enable_nginx_vhost ${SERVICE}
    
    infoText "Enable ${SERVICE} - Link php-fpm pool app config to pool.d/..."
    enable_phpfpm_app ${SERVICE}
    
    # if we are the ZED instance, init ENV
    if [ "${SERVICE}" = "zed" ]; then
      infoText "init external services (DBMS, ES)"
      /data/bin/entrypoint.sh optimized_init
    fi
    
  done
}


start_services() {
  labelText "Starting enabled services $ENABLED_SERVICES"
  
  # fix error with missing event log dir
  mkdir -p /data/shop/data/$SPRYKER_SHOP_CC/logs/
  
  # might be dropped in optimized mode
  # generate_configurations
  
  # TODO: increase security by making this more granular
  chown -R www-data: /data/logs /data/shop
  
  # starts nginx daemonized, to start php-fpm in background
  # check if nginx failed...
  nginx && php-fpm --nodaemonize
}

execute_console_command() {
  infoText "execute 'console $@'"
  vendor/bin/console $@
}


exec_hooks() {
    hook_d=$1
    if [ -d "$hook_d" ]; then
      for f in `find $hook_d -type f -name '*.sh'`; do
        infoText "Executing hook script: $f"
        source $f
      done
    fi
}

wait_for_service() {
  until nc -z $1 $2; do
    echo "waiting for $1 to come up..."
    sleep 1
  done
  
  echo "$1 seems to be up, port is open"
}


# build steps from `console setup:install`
# DeleteAllCachesConsole::COMMAND_NAME,
# RemoveGeneratedDirectoryConsole::COMMAND_NAME,
# PropelInstallConsole::COMMAND_NAME => ['--' . PropelInstallConsole::OPTION_NO_DIFF => true],
# GeneratorConsole::COMMAND_NAME,
# InitializeDatabaseConsole::COMMAND_NAME,
# BuildNavigationConsole::COMMAND_NAME,
# SearchConsole::COMMAND_NAME,


case $1 in 
    run_yves)
      ENABLED_SERVICES="yves"
      enable_services
      start_services
      ;;

    run_zed)
      ENABLED_SERVICES="zed"
      enable_services
      start_services
      ;;

    run_yves_and_zed)
      ENABLED_SERVICES="yves zed"
      enable_services
      start_services
      ;;

    generate_code_and_assets)
    
        # NOTE: unused, just for a clear overview about the complete setup/init process and it's order
    
        # ============= install_dependencies ===============
    
            if [ "${APPLICATION_ENV}x" != "developmentx" ]; then
              infoText "Installing required NPM dependencies..."
              $NPM install --only=production
              infoText "Installing required PHP dependencies..."
              php /data/bin/composer.phar install --prefer-dist --no-dev
            else
              infoText "Installing required NPM dependencies (including dev) ..."
              $NPM install
              infoText "Installing required PHP dependencies (including PHP) ..."
              php /data/bin/composer.phar install --prefer-dist
            fi
            php /data/bin/composer.phar clear-cache

            # installs antelope dependencies
            # Install all project dependencies
            # requires python binary!
            apk add python
            $ANTELOPE install
    
    
    
        # ============= generate_zed_code ===============
            
            infoText "Propel - Copy schema files ..."
            # Copy schema files from packages to generated folder
            $CONSOLE propel:schema:copy

            infoText "Propel - Build models ..."
            # Build Propel2 classes
            $CONSOLE propel:model:build

            infoText "Propel - Removing old migration plans ..."
            rm -f $SHOP/src/Orm/Propel/*/Migration_pgsql/*
            
            infoText "Zed - generate navigation cache files"
            # [application:build-navigation-cache] Build the navigation tree and persist it
            $CONSOLE navigation:build-cache
    
            mkdir -pv /data/shop/assets/Yves /data/shop/assets/Zed
        
        # ============= generate_configurations ===============
        
            # propel code
            # Write Propel2 configuration
            # any, should be service instance independend
            $CONSOLE propel:config:convert
        
        # ============= build_assets_for_zed ===============
        
            # assets
            # time: any, static code/assets generator
            $ANTELOPE build zed
        
        # ============= build_assets_for_yves ===============
        
            # time: any, static code/assets generator
            $ANTELOPE build yves
        
        # ============= generate_shared_code ===============
        
            # FIXME the following line is workaround:
            #   (1) setup:search must be run at runtime 
            #   (2) therefore ./src/Generated needs to be a shared volume
            #   (3) thats why the transfer objects generated during build time are not available anymore
            #   (4) but we need them there, because propel generation relies on these transfer objects
            #   (5) and thats why we need to regenerate them here 
            # If search:setup task has been split up into a build and init time part, we are able to clean this up
            
            
            # zed <-> yves transfer objects
            # Generates transfer objects from transfer XML definition files
            # time: any, static code generator
            $CONSOLE transfer:generate
        
        
            # FIXME //TRANSLIT isn't supported with musl-libc, by intension!
            # see https://github.com/akrennmair/newsbeuter/issues/364#issuecomment-250208235
            sed -i 's#//TRANSLIT##g'  /data/shop/vendor/spryker/util-text/src/Spryker/Service/UtilText/Model/Slug.php
        
        
        # ============= init_shared ===============
        
            infoText "Propel - Converting configuration ..."
            # Write Propel2 configuration
            $CONSOLE propel:config:convert

            # FIXME Does this task makes sense during init stage? Since it works on
            # ./data which is not a shared volume? 
            infoText "Cleaning cache ..."
            # Deletes all cache files from /data/{Store}/cache for all stores
            $CONSOLE cache:delete-all

            infoText "Create Search Index and Mapping Types; Generate Mapping Code."
            # This command will run installer for search
            # migth be split into:
            #   setup:search:index-map              This command will generate the PageIndexMap without requiring the actual Elasticsearch index
            $CONSOLE setup:search

            infoText "Build Zeds Navigation Cache ..."
            # in 2.11, this is missing? => replaced by navigation:build-cache (it's currently the same/an alias!)
            $CONSOLE application:build-navigation-cache

            exec_hooks "$SHOP/docker/init.d/Shared"
        
        
        # ============= init_zed ===============
        
            infoText "Propel - Create database ..."
            # Create database if it does not already exist
            $CONSOLE propel:database:create

            infoText "Propel - Insert PG compatibility ..."
            # Adjust Propel-XML schema files to work with PostgreSQL
            $CONSOLE propel:pg-sql-compat

            infoText "Propel - Create schema diff ..."
            # Generate diff for Propel2
            $CONSOLE propel:diff

            infoText "Propel - Migrate Schema ..."
            # Migrate database
            $CONSOLE propel:migrate

            infoText "Propel - Initialize database ..."
            # Fill the database with required data
            $CONSOLE setup:init-db

            exec_hooks "$SHOP/docker/init.d/Zed"

            infoText "Jenkins - Register setup wide cronjobs ..."
            # FIXME [bug01] until the code of the following cronsole command completely
            # relies on API calls, we need to workaround the issue with missing local
            # jenkins job definitions.
            mkdir -p /tmp/jenkins/jobs
            # Generate Jenkins jobs configuration
            $CONSOLE setup:jenkins:generate
        
        
        # ============= init_yves ===============
        
            exec_hooks "$SHOP/docker/init.d/Yves"
        
        ;;
    
    
    
    optimized_build)
    
        # rule of thumb:
        # zed is able to work without yves, so generate zed data first!
        
        
        # ============= install dependencies PHP/NodeJS ===============
        
        
        infoText "Installing required PHP dependencies..."
        
        if [ "${APPLICATION_ENV}x" != "developmentx" ]; then
          COMPOSER_ARGUMENTS="--no-dev"
        fi
        
        php /data/bin/composer.phar install --prefer-dist $COMPOSER_ARGUMENTS
        php /data/bin/composer.phar clear-cache # Clears composer's internal package cache
        
        
        # install dependencies for building asset
        # --with-dev is required to install spryker/oryx (works behind npm run x)
        infoText "Installing required NPM dependencies..."
        $NPM install --with-dev
        
        # as we are collecting assets from various vendor/ composer modules
        # we also need to install possible assets-build dependencies from those
        # modules
        for i in `find vendor/ -name 'package.json' | egrep 'assets/(Zed|Yves)/package.json'`; do
          cd `dirname $i`
          $NPM install
          cd $WORKDIR
        done
        
        # ============= build assets ===============
        
        infoText "Build assets for Yves/Zed"
        
        # TODO: add zed:prod and yves:prod possibility
        $NPM run zed
        $NPM run yves
    
        # ============= ORM code / schema generation ===============
        
        infoText "Propel - Copy schema files ..."
        # Copy schema files from packages to generated folder
        $CONSOLE propel:schema:copy
        
        
        # ============= generate_shared_code ===============
        
        # zed <-> yves transfer objects
        # Generates transfer objects from transfer XML definition files
        # time: any, static code generator
        $CONSOLE transfer:generate
        
        infoText "Create Search Index and Mapping Types; Generate Mapping Code."
        # This command will run installer for search
        # migth be split into:
        #   setup:search:index-map              This command will generate the PageIndexMap without requiring the actual Elasticsearch index
        $CONSOLE setup:search:index-map
    
        # FIXME //TRANSLIT isn't supported with musl-libc, by intension!
        # see https://github.com/akrennmair/newsbeuter/issues/364#issuecomment-250208235
        sed -i 's#//TRANSLIT##g'  /data/shop/vendor/spryker/util-text/src/Spryker/Service/UtilText/Model/Slug.php
        
        
        infoText "Build Zeds Navigation Cache ..."
        $CONSOLE navigation:build-cache
        
        ;;
    
    optimized_init)
        
        # ElasticSearch init
        
        wait_for_service $ES_HOST $ES_PORT
        $CONSOLE setup:search

        # SQL Database
        
        wait_for_service $ZED_DB_HOST $ZED_DB_PORT
        
        infoText "Propel - Insert PG compatibility ..."
        # Adjust Propel-XML schema files to work with PostgreSQL
        $CONSOLE propel:pg-sql-compat
        
        infoText "Propel - Converting configuration ..."
        # Write Propel2 configuration
        $CONSOLE propel:config:convert

        infoText "Propel - Build models ..."
        # Build Propel2 classes
        $CONSOLE propel:model:build

        infoText "Propel - Create database ..."
        # Create database if it does not already exist
        $CONSOLE propel:database:create
        
        infoText "Propel - Create schema diff ..."
        # Generate diff for Propel2
        $CONSOLE propel:diff

        infoText "Propel - Migrate Schema ..."
        # Migrate database
        $CONSOLE propel:migrate

        infoText "Propel - Initialize database ..."
        # Fill the database with required data
        $CONSOLE setup:init-db
        
        # Jenkins
        
        wait_for_service $JENKINS_HOST $JENKINS_PORT
        
        infoText "Jenkins - Register setup wide cronjobs ..."
        # FIXME [bug01] until the code of the following cronsole command completely
        # relies on API calls, we need to workaround the issue with missing local
        # jenkins job definitions.
        mkdir -p /tmp/jenkins/jobs
        # Generate Jenkins jobs configuration
        $CONSOLE setup:jenkins:generate
        
        # Customer hooks
        
        exec_hooks "$SHOP/docker/init.d/Shared"
        exec_hooks "$SHOP/docker/init.d/Zed"
        exec_hooks "$SHOP/docker/init.d/Yves"
        
    ;;
    
    *)
        #generate_configurations
        sh -c "$*"
        ;;
esac
