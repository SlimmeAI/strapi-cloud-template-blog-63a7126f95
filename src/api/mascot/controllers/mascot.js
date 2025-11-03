'use strict';

/**
 * mascot controller
 */

const { createCoreController } = require('@strapi/strapi').factories;

module.exports = createCoreController('api::mascot.mascot');
