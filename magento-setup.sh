#!/usr/bin/env bash

if [ -z "${ALGOLIA_APPLICATION_ID}" ]; then
  echo "Missing env var ALGOLIA_APPLICATION_ID"
  exit 1
fi

if [ -z "${ALGOLIA_ADMIN_KEY}" ]; then
  echo "Missing env var ALGOLIA_ADMIN_KEY"
  exit 1
fi

if [ -z "${ALGOLIA_SEARCH_KEY}" ]; then
  echo "Missing env var ALGOLIA_SEARCH_KEY"
  exit 1
fi

printf "Which magento version do you want to install ?\n"
read -p "Release: [2.4.7] " MAGENTO_VERSION
MAGENTO_VERSION=${MAGENTO_VERSION:-2.4.7}

printf ""
read -p "Edition: [COMMUNITY/enterprise] " MAGENTO_EDITION
MAGENTO_EDITION=${MAGENTO_EDITION:-community}

if [ "$MAGENTO_EDITION" = "enterprise" ]
then
  MAGENTO_EDITION_SHORT="ee"
else
  MAGENTO_EDITION_SHORT="ce"
fi

echo "Installing version $MAGENTO_VERSION $MAGENTO_EDITION..."

VERSION_DIR=${MAGENTO_VERSION//./}
INSTALL_DIR="magento-"$MAGENTO_EDITION_SHORT-${VERSION_DIR//-/}

if [ -d "$INSTALL_DIR" ]; then
  read -p "$INSTALL_DIR does exist. Do you want to delete it ? [y,N] " CONFIRM_DELETION
  CONFIRM_DELETION=${CONFIRM_DELETION:-n}
  if [ "$CONFIRM_DELETION" = "y" ]
  then
    if [ -d "$INSTALL_DIR/bin" ]; then
      cd "$INSTALL_DIR" || exit
      bin/docker-compose down
      cd ..
    fi
    rm -fr "$INSTALL_DIR"
  else
    exit
  fi
fi

######## MAGENTO INSTALL ########
mkdir "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit
curl -s https://raw.githubusercontent.com/markshust/docker-magento/master/lib/template | bash
# TODO update compose.yaml =image: markoshust/magento-php:8.2-fpm-2 (for Magento 2.4.6)
bin/download "${MAGENTO_VERSION}" "$MAGENTO_EDITION"
bin/setup "$INSTALL_DIR".test

######## ADMIN UPDATES ########
bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth Magento_TwoFactorAuth
bin/magento c:f
bin/magento setup:upgrade
bin/magento config:set admin/security/session_lifetime 31536000

######## SAMPLE DATA INSTALL ########
bin/magento sampledata:deploy
bin/magento setup:upgrade

######## ALGOLIA INSTALL ########
cd src/app/code || exit
mkdir Algolia
cd Algolia || exit
git clone https://github.com/algolia/algoliasearch-magento-2.git
mv algoliasearch-magento-2 AlgoliaSearch
cd ../../../..
bin/magento module:enable Algolia_AlgoliaSearch
bin/magento setup:upgrade

######## PHP CLIENT INSTALL ########
bin/composer require algolia/algoliasearch-client-php "^4.0"
bin/copyfromcontainer vendor/algolia # So that the classes appear in PHPStorm

######## FIRST INDEXING ########
ALGOLIA_PREFIX=${INSTALL_DIR//-/_}
bin/magento config:set algoliasearch_credentials/credentials/application_id "${ALGOLIA_APPLICATION_ID}"
bin/magento config:set algoliasearch_credentials/credentials/api_key "${ALGOLIA_ADMIN_KEY}"
bin/magento config:set algoliasearch_credentials/credentials/search_only_api_key "${ALGOLIA_SEARCH_KEY}"
bin/magento config:set algoliasearch_credentials/credentials/index_prefix "${ALGOLIA_PREFIX}"_
bin/magento indexer:reindex

######## DISPLAY ########
echo "################################################"
echo "Website URL: https://$INSTALL_DIR.test"
echo "Admin URL: https://$INSTALL_DIR.test/admin (john.smith / password123)"
echo "PhpMyAdmin URL: http://localhost:8080/ (root / magento)"
echo "################################################"