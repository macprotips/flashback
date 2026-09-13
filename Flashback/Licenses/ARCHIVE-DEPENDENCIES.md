# Archive reader dependency

Flashback packages Apache Commons Compress **1.28.0** and its required Apache
Commons IO **2.20.0** and Commons Lang **3.18.0** runtimes inside its private
`JavaRunner.jar` solely to read legacy ZIP methods, including Imploding
(method 6). It does not execute archived content.

The build requires `python3 Flashback/fetch-archive-dependencies.py` before
compilation. The script fetches and SHA-256 verifies these upstream artifacts
into ignored `vendor/archive/`:

| Artifact | URL | SHA-256 |
| --- | --- | --- |
| Runtime JAR | https://repo.maven.apache.org/maven2/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar | `e1522945218456f3649a39bc4afd70ce4bd466221519dba7d378f2141a4642ca` |
| Corresponding source | https://dlcdn.apache.org/commons/compress/source/commons-compress-1.28.0-src.tar.gz | `5c870fa454221b24c81d10a28031a9183d55f2baab92c160ecc985e51a387662` |
| Commons IO runtime JAR | https://repo.maven.apache.org/maven2/commons-io/commons-io/2.20.0/commons-io-2.20.0.jar | `df90bba0fe3cb586b7f164e78fe8f8f4da3f2dd5c27fa645f888100ccc25dd72` |
| Commons IO corresponding source | https://repo.maven.apache.org/maven2/commons-io/commons-io/2.20.0/commons-io-2.20.0-sources.jar | `7a87277538cce40da6389a7163a4d9458bc7a9c39937a329881b91d144be8e0d` |
| Commons Lang runtime JAR | https://repo.maven.apache.org/maven2/org/apache/commons/commons-lang3/3.18.0/commons-lang3-3.18.0.jar | `4eeeae8d20c078abb64b015ec158add383ac581571cddc45c68f0c9ae0230720` |
| Commons Lang corresponding source | https://repo.maven.apache.org/maven2/org/apache/commons/commons-lang3/3.18.0/commons-lang3-3.18.0-sources.jar | `b15732a13e40df7f07c30f2cb8572874798e8dde581f1398943d2ad3765bafaa` |

All three Apache components are licensed under Apache-2.0. Their fetched source
artifacts are the corresponding source for the packaged classes; unmodified
LICENSE and NOTICE files are copied to `vendor/archive/` by the fetch script.
The application ships their notices in `Licenses/ARCHIVE-NOTICE.txt`.
