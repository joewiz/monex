/*
 * SPDX LGPL-2.1-or-later
 * Copyright (C) 2014 The eXist-db Authors
 */
/// <reference types="cypress" />

describe('index preview', () => {
  const collection = '/db/monex-indexes-analysis-test'
  const doc = `${collection}/volume.xml`
  // The preview needs ft:field-text and ft:analyze, and the fixture's div needs analyzer chains
  // (eXist-db/exist#6908) to be indexed at all: on an eXist without them, the specs are skipped.
  let previewSupported = false

  function restQuery (query) {
    const baseUrl = new URL(Cypress.config('baseUrl'))
    return cy.request({
      method: 'POST',
      url: `${baseUrl.protocol}//${baseUrl.host}/exist/rest/db`,
      auth: { username: 'admin', password: '' },
      form: true,
      body: { _query: query }
    }).its('body')
  }

  function preview (params) {
    cy.visit({ url: 'index-preview.html', qs: { collection, ...params } })
  }

  before('store a collection with analyzer chains and unstored fields', () => {
    cy.fixture('indexes-analysis-setup.xq').then((query) => {
      restQuery(query).should('contain', 'ok')
    })
    restQuery(
      'exists(function-lookup(QName("http://exist-db.org/xquery/lucene", "analyze"), 4)) and ' +
      `exists(collection("${collection}")/ft:index-keys-for-field("monex-ia-delimited", (), function ($k, $d) { $k }, 1))`
    ).then((body) => {
      previewSupported = String(body).includes('true')
    })
  })

  after('remove it', () => {
    cy.fixture('indexes-analysis-teardown.xq').then((query) => {
      restQuery(query).should('contain', 'ok')
    })
  })

  beforeEach('log in', function () {
    if (!previewSupported) {
      this.skip()
    }
    cy.loginApi()
  })

  it('should be reached from the collection page, and choose a node by document and XPath', () => {
    cy.visit(`collection.html?collection=${collection}`)
    cy.contains('.indexes-preview-link a', 'Preview a node').click()
    cy.get('.indexes-intro').should('contain', 'as the analyzer reports them')
    cy.get('.preview-chooser select#doc').should('contain', doc)
    cy.get('.preview-chooser input#xpath').should('have.value', '//div')
    cy.get('.preview-chooser button[type=submit]').click()
    cy.contains('.preview-node-list .indexes-meta-primary', '2 nodes')
    cy.contains('.preview-node-list a', '/volume[1]/div[1]').click()
    cy.get('.preview-node-path').should('have.text', '/volume[1]/div[1]')
  })

  it('should show an index\'s extracted text, with ignore and inline applied, and its tokens', () => {
    preview({ doc, xpath: '//div[@id="d1"]' })
    cy.get('.preview-text[data-indexed="div"] > .preview-source').within(() => {
      cy.get('.preview-source-text')
        .should('contain', 'The treaty was signed in Paris')
        .and('not.contain', 'A note on the treaty')
      cy.root().should('contain', 'ignore note').and('contain', 'inline hi')
    })
    cy.get('.preview-text[data-indexed="div"] > .preview-tokens').within(() => {
      cy.contains('.preview-term', /^treaty$/)
      // a stopword of the stopped analyzer
      cy.contains('.preview-term', /^the$/).should('not.exist')
    })
  })

  it('should show an expression\'s value, without ignore, and both chains\' tokens', () => {
    preview({ doc, xpath: '//div[@id="d1"]', 'q-field': 'monex-ia-delimited' })
    cy.get('.preview-field[data-field="monex-ia-delimited"]').within(() => {
      cy.get('.preview-source-text').first().should('contain', 'A note on the treaty')
      cy.get('.preview-tokens').first()
        .should('contain', 'Index chain tokens')
        .contains('.preview-term', /^f16$/)
      cy.get('.preview-tokens').eq(1).should('contain', 'Query chain tokens')
      cy.get('.preview-tokens').eq(1).contains('.preview-term', /^f16$/).should('not.exist')
    })
  })

  it('should say why a field has no value, and not analyze a typed field', () => {
    preview({ doc, xpath: '//div[@id="d2"]' })
    cy.get('.preview-field[data-field="monex-ia-dated"] .preview-no-value')
      .should('contain', 'its condition, @when, is false')
    preview({ doc, xpath: '//div[@id="d1"]' })
    cy.get('.preview-field[data-field="monex-ia-year"]').within(() => {
      cy.root().invoke('attr', 'open', 'open')
      cy.get('.preview-source-text').should('have.text', '1783')
      cy.get('.preview-tokens').should('not.exist')
    })
  })

  it('should analyze a query string for a field, and mark the terms the node has', () => {
    preview({ doc, xpath: '//div[@id="d1"]' })
    cy.get('.preview-query select#q-field').select('monex-ia-delimited')
    cy.get('.preview-query input#q').type('F16 fighters')
    cy.get('.preview-query button[type=submit]').click()
    cy.get('.preview-query-result').within(() => {
      cy.contains('.preview-match', 'f16')
      cy.contains('.preview-no-match', 'fighters')
    })
  })

  it('should be reached from a term\'s hits', () => {
    cy.visit(`index-keys.html?collection=${collection}&index=lucene-index&show-keys-by=field&field=monex-ia-unstored`)
    cy.contains('tr', /^\s*agreed/).contains('a', 'Preview nodes').click()
    cy.contains('.preview-node-list .indexes-meta-context', 'the term "agreed"')
    cy.get('.preview-node-list tbody tr').should('have.length', 1)
    cy.get('.preview-node-list tbody a').click()
    cy.get('.preview-node-path').should('have.text', '/volume[1]/div[1]')
  })

  it('should say when there is no such node', () => {
    preview({ doc, 'node-id': '9.9.9' })
    cy.contains('.indexes-empty-title', 'No node 9.9.9')
  })
})
