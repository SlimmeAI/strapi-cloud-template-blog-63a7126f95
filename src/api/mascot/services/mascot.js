'use strict';

/**
 * mascot service
 */

const { createCoreService } = require('@strapi/strapi').factories;

module.exports = createCoreService('api::mascot.mascot');
