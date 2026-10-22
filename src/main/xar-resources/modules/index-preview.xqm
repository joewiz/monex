(:
 : SPDX LGPL-2.1-or-later
 : Copyright (C) 2014 The eXist-db Authors
 :)
xquery version "3.1";

(:
    Module: Index preview: shows, for a node, how the Lucene indexing pipeline sees it: the text each index and
    field on the node gets, and the tokens each one's analyzer makes of it, for its index chain and its query chain;
    and a query string's tokens for a field, to see why a search does or doesn't match.
:)

module namespace preview="http://exist-db.org/xquery/admin-interface/index-preview";

declare namespace cc="http://exist-db.org/collection-config/1.0";

import module namespace indexes="http://exist-db.org/xquery/admin-interface/indexes" at "indexes.xqm";
import module namespace templates="http://exist-db.org/xquery/html-templating";

declare variable $preview:collection := request:get-parameter('collection', '');
declare variable $preview:doc := request:get-parameter('doc', '');
declare variable $preview:node-id := request:get-parameter('node-id', '');
declare variable $preview:xpath := request:get-parameter('xpath', '');
declare variable $preview:field := request:get-parameter('field', '');
declare variable $preview:term := request:get-parameter('term', '');
declare variable $preview:q := request:get-parameter('q', '');
declare variable $preview:q-field := request:get-parameter('q-field', '');

(: the most nodes a selection or a term's hits lists :)
declare variable $preview:max-nodes := 50;

(: ft:field-text and ft:analyze are new in eXist 7; looked up, so the page says so on an eXist without them :)
declare variable $preview:field-text := function-lookup(QName("http://exist-db.org/xquery/lucene", "field-text"), 2);
declare variable $preview:analyze := function-lookup(QName("http://exist-db.org/xquery/lucene", "analyze"), 4);

declare
    %templates:wrap
function preview:current-node($node as node(), $model as map(*)) {
    if ($preview:node-id ne '') then
        'Node ' || $preview:node-id || ' in ' || $preview:doc
    else if ($preview:term ne '') then
        'Nodes with "' || $preview:term || '" in ' || $preview:field
    else
        'Index preview'
};

(:
    Main function: a node's preview; or the nodes an XPath selects, or a term's hits, to choose one from; or the form
    to choose a node with
:)
declare
    %templates:wrap
function preview:show($node as node(), $model as map(*)) {
    let $xconf := preview:xconf($preview:collection)
    let $lucene := $xconf/cc:index/cc:lucene
    return
        if (empty($preview:field-text) or empty($preview:analyze)) then
            <div class="callout callout-warning">
                The index preview needs <code>ft:field-text</code> and <code>ft:analyze</code>, which this
                version of eXist doesn't have.
            </div>
        else if (empty($lucene)) then
            <div class="indexes-empty-state">
                <p class="indexes-empty-title">No Lucene configuration for this collection</p>
                <p class="indexes-empty-hint">Expected <code>/db/system/config{$preview:collection}</code> with a
                    <code>collection.xconf</code> file configuring a <code>lucene</code> index.</p>
            </div>
        else if ($preview:node-id ne '' and $preview:doc ne '') then
            let $target := util:node-by-id(doc($preview:doc), $preview:node-id)
            return
                if (empty($target)) then
                    preview:not-found('No node ' || $preview:node-id || ' in ' || $preview:doc)
                else
                    preview:node-preview($target, $lucene)
        else if ($preview:term ne '' and $preview:field ne '') then
            preview:node-list(preview:term-hits($lucene, $preview:field, $preview:term), $lucene,
                'Nodes whose field "' || $preview:field || '" has the term "' || $preview:term || '"')
        else if ($preview:xpath ne '') then
            let $selected := preview:select($xconf, $preview:xpath)
            return
                if (count($selected) eq 1) then
                    preview:node-preview($selected, $lucene)
                else
                    preview:node-list($selected, $lucene, 'Nodes selected by ' || $preview:xpath)
        else
            preview:chooser($preview:collection, $lucene)
};

declare function preview:not-found($message as xs:string) as element(div) {
    <div class="indexes-empty-state">
        <p class="indexes-empty-title">{$message}</p>
    </div>
};

(:
    Helper function: the collection.xconf of a data collection
:)
declare function preview:xconf($collection as xs:string) as element(cc:collection)? {
    let $config := '/db/system/config' || $collection
    return
        if ($collection ne '' and xmldb:collection-available($config)) then
            collection($config)/cc:collection[util:collection-name(.) eq $config][1]
        else ()
};

(:
    Helper function: the namespace declarations of a collection.xconf, for an XPath that uses its prefixes
:)
declare function preview:namespace-declarations($xconf as element(cc:collection)) as xs:string {
    string-join(
        for $prefix in distinct-values(($xconf, $xconf//cc:index) ! in-scope-prefixes(.))
        where not($prefix = ('', 'xml'))
        return 'declare namespace ' || $prefix || '="' || namespace-uri-for-prefix($prefix, ($xconf//cc:index, $xconf)[1]) || '"; '
    )
};

(:
    Helper function: the nodes an XPath selects in the document, or in the collection without one
:)
declare function preview:select($xconf as element(cc:collection), $xpath as xs:string) as node()* {
    let $context := if ($preview:doc ne '') then doc($preview:doc) else collection($preview:collection)
    let $path := if (starts-with($xpath, '/')) then '.' || $xpath else './' || $xpath
    return
        subsequence(
            for $root in $context
            return util:eval-inline($root, preview:namespace-declarations($xconf) || $path),
            1,
            $preview:max-nodes + 1
        )
};

(:
    Helper function: the nodes of the collection whose field has a term, as the term is in the index
:)
declare function preview:term-hits($lucene as element(cc:lucene), $field as xs:string, $term as xs:string) as node()* {
    let $text := ($lucene//cc:field[@name eq $field]/parent::cc:text)[1]
    let $xconf := $lucene/ancestor::cc:collection
    let $path := if ($text/@qname) then '//' || $text/@qname else $text/@match/string()
    return
        if (empty($text)) then ()
        else
            subsequence(
                util:eval(
                    preview:namespace-declarations($xconf)
                    || 'declare variable $field external; declare variable $term external; '
                    || 'collection("' || $preview:collection || '")' || $path
                    || '[ft:query-field($field, <query><term>{$term}</term></query>)]',
                    false(),
                    (xs:QName('field'), $field, xs:QName('term'), $term)
                ),
                1,
                $preview:max-nodes + 1
            )
};

(:
    Helper function: a list of nodes, each linked to its preview
:)
declare function preview:node-list($nodes as node()*, $lucene as element(cc:lucene), $title as xs:string) as element(div) {
    <div class="preview-node-list">
        <div class="indexes-meta-block">
            <p class="indexes-meta-primary">{
                if (count($nodes) gt $preview:max-nodes) then
                    'The first ' || $preview:max-nodes || ' nodes'
                else
                    count($nodes) || (if (count($nodes) eq 1) then ' node' else ' nodes')
            }</p>
            <p class="indexes-meta-context">{$title} in <a href="collection.html?collection={$preview:collection}">{$preview:collection}</a></p>
        </div>
        {
            if (empty($nodes)) then
                preview:not-found('No nodes')
            else
                <div class="indexes-table-wrap">
                    <table class="table table-striped indexes-definitions">
                        <thead>
                            <tr>
                                <th>Node</th>
                                <th>Document</th>
                                <th>Text</th>
                            </tr>
                        </thead>
                        <tbody>{
                            for $n in subsequence($nodes, 1, $preview:max-nodes)
                            let $text := normalize-space(string-join($preview:field-text($n, ()), ' '))
                            return
                                <tr>
                                    <td><a href="{preview:node-href($n)}">{preview:node-path($n)}</a></td>
                                    <td>{document-uri(root($n))}</td>
                                    <td class="indexes-type-detail">{
                                        if (string-length($text) gt 120) then substring($text, 1, 120) || '…' else $text
                                    }</td>
                                </tr>
                        }</tbody>
                    </table>
                </div>
        }
    </div>
};

declare function preview:node-href($node as node()) as xs:string {
    'index-preview.html?collection=' || encode-for-uri($preview:collection)
        || '&amp;doc=' || encode-for-uri(document-uri(root($node)))
        || '&amp;node-id=' || util:node-id($node)
};

(:
    Helper function: a readable path to a node, with each step's position among its siblings of that name
:)
declare function preview:node-path($node as node()) as xs:string {
    string-join(
        for $step in $node/ancestor-or-self::*
        let $position := count($step/preceding-sibling::*[node-name(.) eq node-name($step)]) + 1
        return '/' || name($step) || '[' || $position || ']'
    )
};

(:
    Helper function: the form to choose a node with: a document of the collection, and an XPath
:)
declare function preview:chooser($collection as xs:string, $lucene as element(cc:lucene)) as element(div) {
    let $docs := subsequence(collection($collection), 1, 200) ! document-uri(.)
    let $first := ($lucene/cc:text)[1]
    let $example := if ($first/@qname) then '//' || $first/@qname else string($first/@match)
    return
        <div class="indexes-toolbar preview-chooser">
            <form method="get" class="form-horizontal" action="index-preview.html" role="form">
                <input type="hidden" name="collection" value="{$collection}"/>
                <div class="form-group">
                    <label for="doc" class="col-sm-2 control-label">Document:</label>
                    <div class="col-sm-6">
                        <select id="doc" name="doc" class="form-control">
                            <option value="">Any document in the collection</option>
                            {
                                for $doc in $docs
                                order by $doc
                                return <option value="{$doc}">{if ($doc eq $preview:doc) then attribute selected {'selected'} else ()}{$doc}</option>
                            }
                        </select>
                    </div>
                </div>
                <div class="form-group">
                    <label for="xpath" class="col-sm-2 control-label">XPath:</label>
                    <div class="col-sm-6">
                        <span class="input-group">
                            <input id="xpath" name="xpath" type="text" class="form-control" value="{($preview:xpath[. ne ''], $example)[1]}"/>
                            <span class="input-group-btn">
                                <button type="submit" class="btn btn-primary" title="Preview">
                                    <span class="glyphicon glyphicon-search"/></button>
                            </span>
                        </span>
                        <p class="help-block">Selects the node to preview; with more than one, lists them to choose from. The collection configuration's namespace prefixes can be used.</p>
                    </div>
                </div>
            </form>
        </div>
};

(:
    Helper function: the text configurations that apply to a node: by its QName, or by a match path that selects it
:)
declare function preview:texts-for-node($node as node(), $lucene as element(cc:lucene)) as element(cc:text)* {
    let $declarations := preview:namespace-declarations($lucene/ancestor::cc:collection)
    for $text in $lucene/cc:text
    where
        if ($text/@qname) then
            let $name := $text/@qname/string()
            let $is-attribute := starts-with($name, '@')
            let $lexical := if ($is-attribute) then substring($name, 2) else $name
            let $uri :=
                if (contains($lexical, ':')) then namespace-uri-for-prefix(substring-before($lexical, ':'), $text)
                else ''
            return
                ($is-attribute eq ($node instance of attribute()))
                and local-name($node) eq replace($lexical, '^.*:', '')
                and namespace-uri($node) eq string($uri)
        else if ($text/@match) then
            let $path := $text/@match/string()
            let $matched := util:eval-inline(root($node), $declarations || (if (starts-with($path, '/')) then '.' else './') || $path)
            return some $m in $matched satisfies $m is $node
        else
            false()
    return $text
};

(:
    Shows a node's preview: for each index on it, its text and tokens, and each of its fields' values and tokens;
    then a query string's tokens for a field
:)
declare function preview:node-preview($node as node(), $lucene as element(cc:lucene)) as element(div) {
    let $texts := preview:texts-for-node($node, $lucene)
    return
        <div class="preview-node">
            <div class="indexes-meta-block">
                <p class="indexes-meta-primary preview-node-path">{preview:node-path($node)}</p>
                <p class="indexes-meta-context">
                    node {util:node-id($node)} in {document-uri(root($node))}
                    · <a href="index-preview.html?collection={encode-for-uri($preview:collection)}&amp;doc={encode-for-uri(document-uri(root($node)))}">choose another node</a>
                </p>
            </div>
            {
                if (empty($texts)) then
                    preview:not-found('No Lucene index applies to this node')
                else
                    for $text in $texts
                    return preview:text-preview($node, $text, $lucene),
                if (exists($texts)) then preview:query-form($node, $texts, $lucene) else ()
            }
        </div>
};

(:
    Helper function: an index's text for the node and its tokens, and its fields'
:)
declare function preview:text-preview($node as node(), $text as element(cc:text), $lucene as element(cc:lucene)) as element(div) {
    let $analyzer-id := $text/@analyzer/string()
    let $content := string-join($preview:field-text($node, ()), ' ')
    return
        <div class="preview-text" data-indexed="{($text/@qname, $text/@match)[1]}">
            <h4 class="indexes-section-title">
                Index on {($text/@qname, $text/@match)[1]/string()}
                {if ($text/@field) then (' · field ', $text/@field/string()) else ()}
            </h4>
            {
                if ($text/@index eq 'no') then
                    <p class="preview-note indexes-item-muted">Not indexed itself (<code>index="no"</code>); only its fields are.</p>
                else (
                    preview:source('Extracted text', $content,
                        "The node's text, with ignore and inline applied" ||
                        (if (($text, $lucene)/(cc:inline | cc:ignore)) then
                            ' (' || string-join((
                                ($text, $lucene)/cc:ignore/@qname ! ('ignore ' || .),
                                ($text, $lucene)/cc:inline/@qname ! ('inline ' || .)
                            ), ', ') || ')'
                        else '')),
                    preview:token-tables($node, (), $content, $lucene, $analyzer-id)
                )
            }
            {
                for $field in $text/cc:field
                return preview:field-preview($node, $field, $lucene)
            }
        </div>
};

(:
    Helper function: a field's values for the node, and the tokens of each
:)
declare function preview:field-preview($node as node(), $field as element(cc:field), $lucene as element(cc:lucene)) as element(details) {
    let $name := $field/@name/string()
    let $values := $preview:field-text($node, $name)
    let $analyzer-id := indexes:field-analyzer-id($field)
    (: with many fields, only the one a query string is analyzed for is open :)
    let $open := count($field/../cc:field) le 3 or $name eq $preview:q-field
    return
        <details class="preview-field" data-field="{$name}">
            {if ($open) then attribute open {'open'} else ()}
            <summary class="preview-field-title">
                Field <code>{$name}</code>
                <span class="indexes-item-muted">{
                    string-join((
                        if ($field/@expression) then 'expression ' || $field/@expression else 'extracted text',
                        if ($field/@if) then 'if ' || $field/@if else (),
                        if ($field/@type) then 'type ' || $field/@type else (),
                        if (indexes:unstored($field)) then 'not stored: computed from the node' else 'stored'
                    ), ' · ')
                }</span>
            </summary>
            {
                if (empty($values)) then
                    <p class="preview-note indexes-item-muted preview-no-value">{
                        if ($field/@if) then 'No value: its condition, ' || $field/@if || ', is false for this node.'
                        else 'No value for this node.'
                    }</p>
                else if (indexes:typed-field($field)) then
                    for $value in $values
                    return preview:source('Value', $value, 'Not analyzed: a typed or binary field is indexed as its value')
                else
                    for $value at $i in $values
                    return (
                        preview:source(
                            if (count($values) gt 1) then 'Value ' || $i || ' of ' || count($values) else 'Value',
                            $value,
                            if ($field/@expression) then "The expression's value; ignore and inline don't apply"
                            else 'The extracted text, with ignore and inline applied'
                        ),
                        preview:token-tables($node, $name, $value, $lucene, $analyzer-id)
                    )
            }
        </details>
};

declare function preview:source($label as xs:string, $text as xs:string, $note as xs:string) as element(div) {
    <div class="preview-source">
        <span class="indexes-chain-label">{$label}</span>
        <span class="indexes-item-muted"> · {$note}</span>
        <pre class="preview-source-text">{$text}</pre>
    </div>
};

(:
    Helper function: the tokens an analyzer makes of a text, for its index chain, and for its query chain if it has
    one
:)
declare function preview:token-tables(
    $node as node(),
    $field as xs:string?,
    $text as xs:string,
    $lucene as element(cc:lucene),
    $analyzer-id as xs:string?
) as element()* {
    let $analyzer := indexes:analyzer-by-id($lucene, $analyzer-id)
    return (
        preview:token-table($text, $preview:analyze($node, $field, $text, map { 'for': 'index' }),
            if ($analyzer/cc:query) then 'Index chain tokens' else 'Tokens', $analyzer-id),
        if ($analyzer/cc:query) then
            preview:token-table($text, $preview:analyze($node, $field, $text, map { 'for': 'query' }),
                'Query chain tokens', $analyzer-id)
        else ()
    )
};

declare function preview:token-table($text as xs:string, $tokens as map(*)*, $label as xs:string, $analyzer-id as xs:string?) as element(div) {
    <div class="preview-tokens">
        <span class="indexes-chain-label">{$label}</span>
        <span class="indexes-item-muted"> · {count($tokens)} · {
            if ($analyzer-id) then (<a href="collection.html?collection={encode-for-uri($preview:collection)}#{indexes:analyzer-anchor($analyzer-id)}">{$analyzer-id}</a>, ' analyzer')
            else 'default analyzer'
        }</span>
        {
            if (empty($tokens)) then
                <p class="indexes-item-muted">No tokens</p>
            else
                <table class="table table-condensed indexes-definitions preview-token-table">
                    <thead>
                        <tr>
                            <th>Position</th>
                            <th>Term</th>
                            <th>Text</th>
                            <th>Start</th>
                            <th>End</th>
                            <th>Length</th>
                            <th>Type</th>
                        </tr>
                    </thead>
                    <tbody>{
                        for $token in $tokens
                        return
                            <tr class="{if ($token?position-length gt 1) then 'preview-token-span' else ()}">
                                <td>{$token?position}{if ($token?position-length gt 1) then '–' || ($token?position + $token?position-length - 1) else ()}</td>
                                <td class="preview-term"><code>{$token?term}</code></td>
                                <td>{substring($text, $token?start, $token?end - $token?start)}</td>
                                <td>{$token?start}</td>
                                <td>{$token?end}</td>
                                <td>{$token?position-length}</td>
                                <td>{$token?type}</td>
                            </tr>
                    }</tbody>
                </table>
        }
    </div>
};

(:
    Helper function: the form to analyze a query string for a field or index on the node, and its tokens, each
    marked by whether the node's text for it has the term
:)
declare function preview:query-form($node as node(), $texts as element(cc:text)+, $lucene as element(cc:lucene)) as element(div) {
    let $fields := $texts/cc:field[not(indexes:typed-field(.))]
    return
        <div class="preview-query">
            <h4 class="indexes-section-title">Analyze a query string</h4>
            <div class="indexes-toolbar">
                <form method="get" class="form-horizontal" action="index-preview.html" role="form">
                    <input type="hidden" name="collection" value="{$preview:collection}"/>
                    <input type="hidden" name="doc" value="{document-uri(root($node))}"/>
                    <input type="hidden" name="node-id" value="{util:node-id($node)}"/>
                    <div class="form-group">
                        <label for="q-field" class="col-sm-2 control-label">Field:</label>
                        <div class="col-sm-4">
                            <select id="q-field" name="q-field" class="form-control">
                                <option value="">the index itself</option>
                                {
                                    for $name in distinct-values($fields/@name)
                                    return <option value="{$name}">{if ($name eq $preview:q-field) then attribute selected {'selected'} else ()}{$name}</option>
                                }
                            </select>
                        </div>
                    </div>
                    <div class="form-group">
                        <label for="q" class="col-sm-2 control-label">Query string:</label>
                        <div class="col-sm-4">
                            <span class="input-group">
                                <input id="q" name="q" type="text" class="form-control" value="{$preview:q}"/>
                                <span class="input-group-btn">
                                    <button type="submit" class="btn btn-primary" title="Analyze">
                                        <span class="glyphicon glyphicon-search"/></button>
                                </span>
                            </span>
                            <p class="help-block">Analyzed with the field's query chain, as the words of a query are. Query syntax, such as <code>AND</code>, quotes or wildcards, isn't parsed here.</p>
                        </div>
                    </div>
                </form>
            </div>
            {
                if ($preview:q ne '') then
                    let $field := if ($preview:q-field ne '') then $preview:q-field else ()
                    let $field-config := $fields[@name eq $field][1]
                    let $analyzer-id :=
                        if ($field-config) then indexes:field-analyzer-id($field-config)
                        else $texts[1]/@analyzer/string()
                    let $node-texts := if ($field) then $preview:field-text($node, $field) else string-join($preview:field-text($node, ()), ' ')
                    let $node-terms := distinct-values($node-texts ! $preview:analyze($node, $field, ., map { 'for': 'index' })?term)
                    let $tokens := $preview:analyze($node, $field, $preview:q, map { 'for': 'query' })
                    return
                        <div class="preview-query-result">
                            {preview:token-table($preview:q, $tokens, 'Query tokens', $analyzer-id)}
                            <ul class="preview-query-matches">{
                                for $term in distinct-values($tokens?term)
                                let $found := $term = $node-terms
                                return
                                    <li class="{if ($found) then 'preview-match' else 'preview-no-match'}">
                                        <code>{$term}</code>
                                        {if ($found) then ' is one of this node''s terms' else ' isn''t one of this node''s terms'}
                                    </li>
                            }</ul>
                        </div>
                else ()
            }
        </div>
};
