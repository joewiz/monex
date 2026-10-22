xquery version "3.1";

(:
 : SPDX LGPL-2.1-or-later
 : Copyright (C) 2014 The eXist-db Authors
 :)

declare variable $collection := "/db/monex-indexes-analysis-test";
declare variable $config := "/db/system/config/db/monex-indexes-analysis-test";

(
    if (xmldb:collection-available($collection)) then xmldb:remove($collection) else (),
    if (xmldb:collection-available($config)) then xmldb:remove($config) else (),
    "ok"
)[last()]
