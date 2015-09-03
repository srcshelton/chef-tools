# chef-tools

Two useful utilities to assist in maintaining collections of chef(-solo)
cookbooks without any further infrastructure.

* `librarian-chef-coverage-check.sh`
    * Run `librarian-chef-coverage-check.sh` from the directory containing your
      [librarian-chef](https://github.com/applicationsonline/librarian-chef)
      `Cheffile` file and `cookbooks` directory to provide a quick overview of
      and cookbook dependencies which exist in installed cookbooks but which
      aren't explicitly locked-down in `Cheffile` itself.

* `cookbooks-update-check.sh`
    * Run `cookbooks-update-check.sh` from the directory contianing your
      `cookbooks` directory in order to compare the local cookbook version with
      the latest advertised by the Opscode SuperMarket API, and notify on
      outdated local cookbooks.

`cookbooks-update-check.sh` requires
[stdlib.sh](https://github.com/srcshelton/stdlib.sh) to be installed in
`/usr/local/lib`.

