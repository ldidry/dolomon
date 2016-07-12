// vim:set sw=4 ts=4 sts=4 ft=javascript expandtab:

window.data = {
    uber: null,
    years: null,
    months: null,
    weeks: null,
    days: null
};
window.morris = null;
function getLang(){
    return (navigator.language || navigator.languages[0]);
}
function graphIt(id) {
    var format      = window.data[id].format;
    var dateFormat  = function (x) { return moment(x).format(format); }
    var labelFormat = function (x) { return moment(x).format(format); }
    if (window.morris === null) {
        window.morris = new Morris.Line({
            // ID of the element in which to draw the chart.
            element: 'graph',
            // Chart data records -- each entry in this array corresponds to a point on
            // the chart.
            data: window.data[id].data,
            // The name of the data record attribute that contains x-values.
            xkey: 'x',
            // A list of names of data record attributes that contain y-values.
            ykeys: ['value'],
            // Labels for the ykeys -- will be displayed when you hover over the
            // chart.
            labels: [i18n.hitsNb],
            dateFormat: dateFormat,
            xLabelFormat: labelFormat,
        });
    } else {
        window.morris.options.dateFormat   = dateFormat;
        window.morris.options.xLabelFormat = labelFormat;
        if (id !== 'uber') {
            window.morris.options.xLabels  = id.replace(/s$/, '');
        } else {
            switch($('#aggregate_by').val()) {
                case 30:
                    window.morris.options.xLabels = '30min';
                    break;
                case 15:
                    window.morris.options.xLabels = '15min';
                    break;
                case 5:
                    window.morris.options.xLabels = '5min';
                    break;
                case 1:
                    window.morris.options.xLabels = 'minute';
                    break;
                default:
                    window.morris.options.xLabels = 'hour';
                    break;
            }
        }
        window.morris.setData(window.data[id].data);
    }
    $('#uber .alert').addClass('hidden');
    $('#uber form').removeClass('hidden');
    $('#uber form input, #uber form select').attr('disabled', null);
    $('#tablist li').removeClass('disabled');
}
function changeInterval(id, min, max) {
    $('#uber .alert').removeClass('hidden');
    var data2  = new Array();
    var data   = window.data[id].data;
    var format = window.data[id].format;
    if (id === 'weeks') {
        format = 'l';
    }
    var mmin   = moment.utc(min, format);
    var mmax   = moment.utc(max, format);
    if (id === 'weeks') {
        mmin = moment.utc(mmin.isoWeek()+' '+mmin.isoWeekYear(), 'W GGGG');
        mmax = moment.utc(mmax.isoWeek()+' '+mmax.isoWeekYear(), 'W GGGG');
        $('#'+id+'-graph-start').data('DateTimePicker').date(mmin);
        $('#'+id+'-graph-stop').data('DateTimePicker').date(mmax);
    }
    if (mmin.isAfter(mmax)) {
        var temp = min;
        min      = max;
        max      = temp;
        mmin     = moment.utc(min, format);
        mmax     = moment.utc(max, format);
        $('#'+id+'-graph-start').data('DateTimePicker').date(mmin);
        $('#'+id+'-graph-stop').data('DateTimePicker').date(mmax);
    }
    data.forEach(function(element, index, array) {
        var m = moment.utc(element.x, 'x');
        if (m.isSameOrAfter(mmin) && m.isSameOrBefore(mmax)) {
            data2.push(element);
        }
    });
    window.morris.setData(data2);
    $('#uber .alert').addClass('hidden');
}
function updateDatePicker(id) {
    var format = window.data[id].format;
    min = moment.utc(window.data[id].min);
    max = moment.utc(window.data[id].max);
    var options = {
        useCurrent: false,
        locale: getLang(),
        sideBySide: true,
        format: format,
    };
    if (id === 'weeks') {
        options['calendarWeeks'] = true;
        options['format'] = 'l';
    }
    if ($('#'+id+'-graph-start').data('DateTimePicker') === undefined || $('#'+id+'-graph-start').data('DateTimePicker') === null) {
        $('#'+id+'-graph-start').datetimepicker(options);
        $('#'+id+'-graph-start').data('DateTimePicker').date(min);
        $('#'+id+'-graph-start').on('dp.hide', function (e) {
            changeInterval(id, $('#'+id+'-graph-start').val(), $('#'+id+'-graph-stop').val());
        });
    } else {
        $('#'+id+'-graph-start').data('DateTimePicker').date(min);
    }
    if ($('#'+id+'-graph-stop').data('DateTimePicker') === undefined || $('#'+id+'-graph-stop').data('DateTimePicker') === null) {
        $('#'+id+'-graph-stop').datetimepicker(options);
        $('#'+id+'-graph-stop').data('DateTimePicker').date(max);
        $('#'+id+'-graph-stop').on('dp.hide', function (e) {
            changeInterval(id, $('#'+id+'-graph-start').val(), $('#'+id+'-graph-stop').val());
        });
    } else {
        $('#'+id+'-graph-stop').data('DateTimePicker').date(max);
    }
}
function createGraph(id, agg) {
    var period = id;
    if (period === 'uber') {
        period = 'hits';
    }
    $('.datepicker').addClass('hidden');
    $('.'+id+'.datepicker').removeClass('hidden');
    var data = { period: period };
    if (agg !== undefined && agg !== null) {
        window.data[id] = null;
        data['aggregate_by'] = agg;
    }
    switch(id) {
        case 'days':
            format = 'ddd ll';
            break;
        case 'weeks':
            format = i18n.weekFormat;
            break;
        case 'months':
            format = 'MMMM YYYY';
            break;
        case 'years':
            format = 'YYYY';
            break;
        default:
            format = 'llll';
            break;
    }
    if (window.data[id] === null) {
        $.ajax({
            method: 'GET',
            url: dataUrl,
            data: data,
            dataType: 'json',
            success: function(data, textStatus, jqXHR) {
                data.data.forEach(function(element, index, array) {
                    element.x = element.x * 1000;
                });
                data.min = data.min * 1000;
                data.max = data.max * 1000;
                var min = data.min;
                var max = data.max;
                window.data[id] = { data: data.data, min: min, max: max, format: format };
                updateDatePicker(id);
                graphIt(id);
            }
        });
    } else {
        updateDatePicker(id);
        graphIt(id);
    }
}
$(document).ready(function() {
    if ($('#tablist a').length > 0) {
        moment.locale(getLang());
        createGraph('years');
        $('#tablist a').click(function(e) {
            e.preventDefault();
            if (!$(this).parent().hasClass('disabled')) {
                $('#tablist li').removeClass('active').addClass('disabled');
                $(this).parent().addClass('active');
                $('#uber .alert').removeClass('hidden');
                $('#uber form input, #uber form select').attr('disabled', 'disabled');
                createGraph($(this).data('targetid'));
            }
        });
        $('#aggregate_by').change(function(e) {
            createGraph('uber', $('#aggregate_by').val());
        });
    }
});
