import { LightningElement, api, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import getDashboardChartData from '@salesforce/apex/DashboardDataController.getDashboardChartData';
import chartjsResource from '@salesforce/resourceUrl/chartjs';

const CHART_COLORS = [
    'rgba(0, 118, 211, 0.8)',
    'rgba(94, 180, 50, 0.8)',
    'rgba(237, 139, 0, 0.8)',
    'rgba(176, 0, 32, 0.8)',
    'rgba(88, 103, 195, 0.8)',
    'rgba(0, 176, 180, 0.8)'
];

const DASHBOARD_TABLE_COLUMNS = [
    {
        label: 'Dashboard Name',
        type: 'button',
        typeAttributes: {
            label: { fieldName: 'name' },
            variant: 'base',
            name: 'view_chart'
        },
        sortable: true
    },
    { label: 'Label', fieldName: 'label', type: 'text', sortable: true },
    { label: 'Folder', fieldName: 'folderName', type: 'text', sortable: true },
    { label: 'Developer Name', fieldName: 'developerName', type: 'text', sortable: true }
];

const API_VERSION = 'v65.0';

export default class DashboardCharts extends LightningElement {
    @api endpoint = '';

    @track dashboards = [];
    @track isLoading = true;
    @track errorMessage = '';

    @track showModal = false;
    @track modalTitle = '';
    @track modalCharts = [];
    @track modalLoading = false;
    @track modalError = '';

    tableColumns = DASHBOARD_TABLE_COLUMNS;
    _chartLib = null;
    _modalChartInstances = [];

    connectedCallback() {
        this.loadData();
    }

    disconnectedCallback() {
        this.destroyModalCharts();
    }

    get hasDashboards() {
        return this.dashboards && this.dashboards.length > 0;
    }

    get cardTitle() {
        return 'Dashboards';
    }

    get hasModalCharts() {
        return this.modalCharts && this.modalCharts.length > 0;
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view_chart' && row && row.id) {
            this.openModal(row);
        }
    }

    openModal(row) {
        this.showModal = true;
        this.modalTitle = row.name || row.label || 'Dashboard';
        this.modalCharts = [];
        this.modalError = '';
        this.modalLoading = true;
        this.destroyModalCharts();
        const path = row.url || `/services/data/${API_VERSION}/analytics/dashboards/${row.id}`;
        this.loadModalChart(path);
    }

    async loadModalChart(endpoint) {
        try {
            const raw = await getDashboardChartData({ endpoint });
            const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
            const chartList = (data && data.charts) ? data.charts : [];
            const title = (data && data.dashboardTitle) ? String(data.dashboardTitle) : this.modalTitle;
            this.modalTitle = title;
            if (chartList.length > 0) {
                if (!this._chartLib) {
                    await loadScript(this, chartjsResource);
                    this._chartLib = window.Chart;
                }
                this.modalCharts = chartList.map((c, i) => ({
                    id: c.id || 'modal-chart-' + i,
                    type: (c.type || 'bar').toLowerCase(),
                    title: c.title || 'Chart ' + (i + 1),
                    labels: Array.isArray(c.labels) ? c.labels : [],
                    datasets: Array.isArray(c.datasets) ? c.datasets : []
                }));
            } else {
                this.modalError = 'No chart data for this dashboard.';
            }
        } catch (e) {
            this.modalError = e.body?.message || e.message || 'Failed to load chart.';
        } finally {
            this.modalLoading = false;
        }
    }

    closeModal() {
        this.showModal = false;
        this.modalCharts = [];
        this.modalError = '';
        this.destroyModalCharts();
    }

    handleModalBackdrop() {
        this.closeModal();
    }

    destroyModalCharts() {
        this._modalChartInstances.forEach((chart) => {
            try {
                chart.destroy();
            } catch (e) {}
        });
        this._modalChartInstances = [];
    }

    renderedCallback() {
        if (!this.showModal || !this._chartLib || !this.hasModalCharts || this._modalChartInstances.length > 0) {
            return;
        }
        const canvases = this.template.querySelectorAll('[data-modal-chart-id]');
        if (!canvases || canvases.length === 0) return;

        requestAnimationFrame(() => {
            if (this._modalChartInstances.length > 0) return;
            canvases.forEach((canvas) => {
                const chartId = canvas.getAttribute('data-modal-chart-id');
                const chartDef = this.modalCharts.find((c) => c.id === chartId);
                if (!chartDef || !canvas.getContext) return;
                const config = this.buildChartConfig(chartDef);
                if (!config) return;
                try {
                    const chart = new this._chartLib(canvas, config);
                    this._modalChartInstances.push(chart);
                } catch (err) {
                    console.error('Chart error ' + chartId, err);
                }
            });
        });
    }

    buildChartConfig(chartDef) {
        const type = ['bar', 'line', 'pie', 'doughnut', 'radar'].includes(chartDef.type) ? chartDef.type : 'bar';
        const datasets = (chartDef.datasets || []).map((ds, i) => ({
            label: ds.label || 'Series ' + (i + 1),
            data: Array.isArray(ds.data) ? ds.data.map((v) => Number(v)) : [],
            backgroundColor: type === 'bar' || type === 'line'
                ? CHART_COLORS[i % CHART_COLORS.length]
                : CHART_COLORS.slice(0, (chartDef.labels || []).length),
            borderColor: type === 'line' ? CHART_COLORS[i % CHART_COLORS.length] : undefined,
            borderWidth: type === 'line' ? 2 : 1,
            fill: type === 'line'
        }));
        return {
            type,
            data: {
                labels: chartDef.labels || [],
                datasets
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: { legend: { display: datasets.length > 0 } },
                scales: type === 'bar' || type === 'line' ? { y: { beginAtZero: true }, x: {} } : undefined
            }
        };
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = '';
        this.dashboards = [];
        try {
            const raw = await getDashboardChartData({ endpoint: this.endpoint || null });
            const data = typeof raw === 'string' ? JSON.parse(raw) : raw;
            if (data && data.dashboards && data.dashboards.length > 0) {
                this.dashboards = data.dashboards.map((row) => ({ ...row }));
            }
        } catch (e) {
            this.errorMessage = e.body?.message || e.message || 'Failed to load dashboards.';
        } finally {
            this.isLoading = false;
        }
    }
}
