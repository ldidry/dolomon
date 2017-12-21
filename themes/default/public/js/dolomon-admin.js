function getUserData(page, nb, sortBy, dir, search) {
    var data    = { page: page, nb: nb, sort_by: sortBy, dir: dir };
    if (search !== undefined && search !== null && search !== '') {
        data.search = search;
    }
    $.ajax({
        method: 'GET',
        url: getUserDataUrl,
        data: data,
        dataType: 'json',
        success: function(data, textStatus, jqXHR) {
            $('.loader').addClass('hidden');
            $('#user-table').removeClass('hidden');
            data.page = parseInt(data.page);

            // Create user table
            var t = new Array();
            data.users.forEach(function(e) {
                t.push(
                    '<tr>',
                        '<td>', e.id, '</td>',
                        '<td class="text-left">', e.login, '</td>',
                        '<td class="text-left">', e.first_name, '</td>',
                        '<td class="text-left">', e.last_name, '</td>',
                        '<td class="text-left">', e.mail, '</td>',
                        '<td>',
                            '<span class="glyphicon glyphicon-', ((e.confirmed === 1) ? 'ok': 'remove') , '" aria-hidden="true"></span>&nbsp;',
                            '<span class="sr-only">', ((e.confirmed === 1) ? i18n.yes : i18n.no), '</span>',
                        '</td>',
                        '<td>', moment(Math.round(e.last_login * 1000)).format('llll'), '</td>',
                        '<td>', e.dolos_nb, '</td>',
                    '</tr>'
                );
            });

            $('#user-table tbody').empty();
            $('#user-table tbody').append(t.join(''));

            // Pagination
            var p = new Array();
            p.push(
                '<nav aria-label="Page navigation">',
                  '<ul class="pagination">',
                    ((data.page === 1) ? '<li class="disabled">' : '<li>'),
                    ((data.page === 1) ? '<a href="#" aria-label="'+i18n.previous+'">' : '<a href="#" aria-label="'+i18n.previous+'" data-page="'+(data.page - 1)+'">'),
                        '<span aria-hidden="true">&laquo;</span>',
                      '</a>',
                    '</li>',
            );
            if (data.page > 4 && data.nb_pages > 5) {
                p.push('<li class="disabled"><a href="#">…</a></li>');
            }
            for (var i = 1; i <= data.nb_pages; i++) {
                if (i >= data.page - 2 && i <= data.page + 2) {
                    p.push(
                        ((data.page === i) ? '<li class="active">' : '<li>'),
                            '<a href="#" data-page="', i, '">', i, '</a>',
                        '</li>'
                    );
                }
            }
            if (data.page < 3 && data.nb_pages > 5) {
                p.push('<li class="disabled"><a href="#">…</a></li>');
            }
            p.push(
                    ((data.page === data.nb_pages) ? '<li class="disabled">' : '<li>'),
                    ((data.page === data.nb_pages) ? '<a href="#" aria-label="'+i18n.next+ '">' : '<a href="#" aria-label="'+i18n.next+'" data-page="'+(data.page + 1)+'">'),
                        '<span aria-hidden="true">&raquo;</span>',
                      '</a>',
                    '</li>',
                  '</ul>',
                '</nav>'
            );
            $('#pagination').empty();
            $('#pagination').append(p.join(''));
            $('#pagination a').click(function(ev) {
                var t = $(this);
                ev.preventDefault();
                $('#pagination a.active').removeClass('active');
                t.addClass('active');
                getUserData(
                    t.data('page'),
                    10,
                    $('#user-table .caret').parent().attr('id'),
                    (($('.dropup').length === 0) ? 'DESC' : 'ASC')
                );
            });
        }
    });
}

function toggleSort() {
    var e      = $(this);
    var dir    = 'DESC';
    var sortBy = e.attr('id');
    if (e.find('.caret').length !== 0) {
        if (e.hasClass('dropup')) {
            e.removeClass('dropup');
        } else {
            e.addClass('dropup');
            dir = 'ASC';
        }
    } else {
        $('#user-table .caret').remove();
        e.append('<span class="caret"></span>');
    }
    getUserData($('#pagination li.active a').data('page'), 10, sortBy, dir, $('#search-user').val());
}

$(document).ready(function() {
    moment.locale(getLang());
    getUserData(settings.page, settings.nb, settings.sortBy, settings.dir, $('#search-user').val());
    $('#'+settings.sortBy).append('<span class="caret"></span>');
    if (settings.dir === 'ASC') {
        $('#'+settings.sortBy).addClass('dropup');
    }

    ['id', 'login', 'first_name', 'last_name', 'mail', 'confirmed', 'last_login', 'dolos_nb'].forEach(function(e) {
        $('#'+e).click(toggleSort);
    });

    $('#search-user').bind('input', function() {
        getUserData(
            1,
            10,
            $('#user-table .caret').parent().attr('id'),
            (($('.dropup').length === 0) ? 'DESC' : 'ASC'),
            $(this).val()
        );
    });

    $('#clear-input').click(function(e) {
        e.preventDefault();
        $('#search-user').val(null);
        getUserData(
            1,
            10,
            $('#user-table .caret').parent().attr('id'),
            (($('.dropup').length === 0) ? 'DESC' : 'ASC')
        );
    });
});
