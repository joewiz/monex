/*
 * SPDX LGPL-2.1-or-later
 * Copyright (C) 2014 The eXist-db Authors
 */
/// <reference types="cypress" />

describe('indexes', () => {
  beforeEach('log in', () => {
    cy.loginApi()
    cy.visit('indexes.html')
  })

  it('should load Browse Indexes', () => {
    cy.get('h1')
      .contains('Indexes')
      .url()
      .should('include', '/monex/indexes.html')
    cy.get('.indexes-kpi').should('be.visible')
    cy.contains('.indexes-kpi .kpi-label', 'With vector stores').should('be.visible')
    cy.contains('.indexes-section-title', 'Configured collections').should('be.visible')
    cy.contains('/db/apps/monex/indexes-test')
      .parents('tr')
      .find('.indexes-vector-summary-badge')
      .should('contain', 'Vector')
    cy.contains('/db/apps/monex/indexes-test').click()
    cy.url().should('include', 'collection.html?collection=/db/apps/monex/indexes-test')
  })

  it('should list vector-field definitions when configured', () => {
    cy.contains('/db/apps/monex/indexes-test').click()
    cy.url().should('include', 'collection.html?collection=/db/apps/monex/indexes-test')
    cy.get('.indexes-kpi').should('be.visible')
    cy.contains('.indexes-kpi .kpi-label', 'Legacy range').should('be.visible')
    cy.contains('.indexes-kpi .kpi-label', 'New range').should('be.visible')
    cy.contains('.indexes-kpi .kpi-label', 'Vector store').should('be.visible')
    cy.contains('.indexes-section-title', 'Index definitions').should('be.visible')
    cy.get('.indexes-definitions th').contains('Detail').should('be.visible')
    cy.get('.indexes-vector-row').should('be.visible')
    cy.contains('test-embedding').should('be.visible')
    cy.get('.vector-stat-badge').contains('KNN').should('be.visible')
    cy.contains('Browse qname').should('be.visible')
    cy.contains('Browse node').should('be.visible')
  })
})

describe('indexes: Lucene analysis', () => {
  const collection = '/db/monex-indexes-analysis-test'
  // An eXist without analyzer chains (eXist-db/exist#6908) drops the configuration of the div, whose fields use
  // them, so it indexes none of its fields: the specs that browse them are skipped there.
  let chainsIndexed = false

  function runFixtureQuery (fixture) {
    const baseUrl = new URL(Cypress.config('baseUrl'))
    return cy.fixture(fixture).then((query) => {
      return cy.request({
        method: 'POST',
        url: `${baseUrl.protocol}//${baseUrl.host}/exist/rest/db`,
        auth: { username: 'admin', password: '' },
        form: true,
        body: { _query: query }
      }).its('body').should('contain', 'ok')
    })
  }

  before('store a collection with analyzer chains and unstored fields', () => {
    runFixtureQuery('indexes-analysis-setup.xq')
    const baseUrl = new URL(Cypress.config('baseUrl'))
    cy.request({
      method: 'POST',
      url: `${baseUrl.protocol}//${baseUrl.host}/exist/rest/db`,
      auth: { username: 'admin', password: '' },
      form: true,
      body: {
        _query: `exists(collection("${collection}")/ft:index-keys-for-field("monex-ia-delimited", (), function ($k, $d) { $k }, 1))`
      }
    }).then((response) => {
      chainsIndexed = String(response.body).includes('true')
    })
  })

  after('remove it', () => {
    runFixtureQuery('indexes-analysis-teardown.xq')
  })

  beforeEach('log in', () => {
    cy.loginApi()
    cy.visit(`collection.html?collection=${collection}`)
  })

  it('should list analyzer classes with their params', () => {
    cy.contains('.indexes-section-title', 'Lucene analyzers').should('be.visible')
    cy.get('#analyzer-_default').should('contain', 'org.apache.lucene.analysis.standard.StandardAnalyzer')
    cy.get('#analyzer-stopped')
      .should('contain', 'stopwords')
      .and('contain', 'org.apache.lucene.analysis.CharArraySet')
      .and('contain', '"the", "of"')
    cy.get('#analyzer-keyword').should('contain', 'KeywordAnalyzer')
  })

  it('should list analyzer chains in order, with their arguments', () => {
    cy.get('#analyzer-cased .indexes-analyzer-chain li').should('have.length', 3)
    cy.get('#analyzer-cased .indexes-chain-tokenizer').should('contain', 'standard')
    cy.get('#analyzer-cased .indexes-chain-filter').eq(1).should('contain', 'asciiFolding')
    cy.get('#analyzer-stripped .indexes-chain-char-filter').should('contain', 'htmlStrip')
  })

  it('should list an analyzer\'s index and query chains', () => {
    cy.get('#analyzer-delimited .indexes-analyzer-chain-group').should('have.length', 2)
    cy.get('#analyzer-delimited .indexes-analyzer-chain-group').eq(0)
      .should('contain', 'index chain')
      .and('contain', 'catenateAll="1"')
    cy.get('#analyzer-delimited .indexes-analyzer-chain-group').eq(1)
      .should('contain', 'query chain')
      .and('not.contain', 'catenateAll')
  })

  it('should show inline and ignore, per text and on lucene', () => {
    cy.get('.indexes-lucene-global')
      .should('contain', 'Applies to every Lucene index')
      .and('contain', '(inline: b)')
      .and('contain', '(ignore: sic)')
    cy.get('tr.indexes-text-row[data-indexed="div"]')
      .should('contain', '(inline: hi)')
      .and('contain', '(ignore: note)')
  })

  it('should link analyzer ids to their definitions', () => {
    cy.contains('tr.indexes-field-row', 'monex-ia-cased')
      .find('a.indexes-analyzer-ref')
      .should('have.attr', 'href', '#analyzer-cased')
    cy.contains('tr.indexes-field-row', 'monex-ia-stored')
      .find('a.indexes-analyzer-ref')
      .should('have.attr', 'href', '#analyzer-stopped')
    cy.get('tr.indexes-text-row[data-indexed="p"]')
      .find('a.indexes-analyzer-ref')
      .should('have.attr', 'href', '#analyzer-stripped')
  })

  it('should flag an analyzer id the configuration doesn\'t define', () => {
    cy.contains('tr.indexes-field-row', 'monex-ia-misnamed')
      .find('.indexes-analyzer-undefined')
      .should('contain', 'not defined')
    cy.contains('tr.indexes-field-row', 'monex-ia-cased')
      .find('.indexes-analyzer-undefined')
      .should('not.exist')
  })

  it('should show fields\' expressions, conditions and types, and whether ignore and inline apply', () => {
    cy.contains('tr.indexes-field-row', 'monex-ia-dated').within(() => {
      cy.get('.indexes-field-expression').should('have.text', 'head')
      cy.get('.indexes-field-if').should('have.text', '@when')
      cy.get('.indexes-field-source').should('contain', "ignore and inline don't apply")
    })
    cy.contains('tr.indexes-field-row', 'monex-ia-year').should('contain', 'xs:integer')
    cy.contains('tr.indexes-field-row', 'monex-ia-unstored').within(() => {
      cy.get('.indexes-field-source').should('contain', 'with ignore and inline applied')
      cy.get('.indexes-field-highlight').should('contain', 'computing the text from the node')
    })
  })

  it('should browse the terms of text fields, stored or not, and the values of keyword fields', function () {
    if (!chainsIndexed) {
      this.skip()
    }
    cy.contains('tr.indexes-field-row', 'monex-ia-unstored').contains('a', 'Browse terms')
    cy.contains('tr.indexes-field-row', 'monex-ia-stored').contains('a', 'Browse terms')
    cy.contains('tr.indexes-field-row', 'monex-ia-id').contains('a', 'Browse values')
    cy.contains('tr.indexes-field-row', 'monex-ia-unstored').contains('a', 'Browse terms').click()
    cy.url().should('include', 'show-keys-by=field').and('include', 'field=monex-ia-unstored')
    cy.contains('.indexes-definitions td', /^treaty$/).should('be.visible')
    cy.contains('.indexes-definitions td', /^agreed$/).should('be.visible')
    // the note is ignored, and the stopwords aren't indexed
    cy.get('.indexes-definitions td').contains(/^note$/).should('not.exist')
    cy.get('.indexes-definitions td').contains(/^the$/).should('not.exist')
  })

  it('should browse the values of keyword and typed fields', function () {
    if (!chainsIndexed) {
      this.skip()
    }
    cy.contains('tr.indexes-field-row', 'monex-ia-id').contains('a', 'Browse values').click()
    cy.url().should('include', 'field.html').and('include', 'field=monex-ia-id')
    cy.contains('.indexes-definitions td', /^d1$/).should('be.visible')
    cy.contains('.indexes-definitions td', /^d2$/).should('be.visible')
    cy.visit(`collection.html?collection=${collection}`)
    cy.contains('tr.indexes-field-row', 'monex-ia-year').within(() => {
      cy.get('a.indexes-analyzer-ref').should('not.exist')
      cy.contains('a', 'Browse values').click()
    })
    cy.contains('.indexes-definitions td', /^1783$/).should('be.visible')
  })

  it('should browse the terms of an index chain', function () {
    if (!chainsIndexed) {
      this.skip()
    }
    cy.visit(`index-keys.html?collection=${collection}&index=lucene-index&show-keys-by=field&field=monex-ia-delimited`)
    cy.contains('.indexes-definitions td', /^f-16$/).should('be.visible')
    cy.contains('.indexes-definitions td', /^f16$/).should('be.visible')
  })
})
