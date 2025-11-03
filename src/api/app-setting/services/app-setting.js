'use strict';

/**
 * app-setting service
 */

const { createCoreService } = require('@strapi/strapi').factories;

module.exports = createCoreService('api::app-setting.app-setting');
