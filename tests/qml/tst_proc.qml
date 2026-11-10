import QtQuick
import QtTest
import "../../shell/lib/proc.js" as Proc

TestCase {
    name: "Proc"

    function test_parses_meminfo() {
        const info = Proc.parseMeminfo("MemTotal: 16000000 kB\nMemAvailable: 8000000 kB\n");
        compare(info.memTotal, 16000000 * 1024);
        compare(info.memAvailable, 8000000 * 1024);
        compare(info.used, 8000000 * 1024);
    }

    function test_parses_cpu_sample() {
        const sample = Proc.parseCpu("cpu  100 0 50 800 20 0 5 0 0 0\ncpu0 50 0 25 400 10 0 2 0 0 0\n");
        compare(sample.total, 975);
        compare(sample.idle, 820);
    }

    function test_parses_netdev_without_loopback() {
        const net = Proc.parseNetdev("Inter-|Receive |Transmit\n face |bytes packets|bytes packets\n    lo: 1 2 0 0 0 0 0 0 3 4 0 0 0 0 0 0\n  eth0: 100 2 0 0 0 0 0 0 50 4 0 0 0 0 0 0\n");
        compare(net.rx, 100);
        compare(net.tx, 50);
    }

    function test_computes_network_throughput() {
        const previous = { rx: 1000, tx: 500 };
        const current = { rx: 3000, tx: 1500 };
        compare(Proc.netRate(previous, current, 2), 1500);
        compare(Proc.netRate(null, current, 2), 0);
        compare(Proc.netRate(previous, current, 0), 0);
    }

    function test_guest_cpu_time_is_not_counted_twice() {
        const sample = Proc.parseCpu("cpu 100 10 50 800 20 0 5 0 30 5\n");
        compare(sample.total, 985);
    }

    function test_per_core_load_follows_core_ids() {
        const previous = Proc.parseCpuCores("cpu0 100 0 0 100\ncpu2 100 0 0 100\ncpu10 100 0 0 100\n");
        const current = Proc.parseCpuCores("cpu10 200 0 0 100\ncpu2 150 0 0 150\ncpu0 100 0 0 200\n");
        const cores = Proc.corePercents(previous, current);
        compare(cores[0].name, "cpu0");
        compare(cores[0].percent, 0);
        compare(cores[1].name, "cpu2");
        compare(cores[1].percent, 50);
        compare(cores[2].name, "cpu10");
        compare(cores[2].percent, 100);
    }

    function test_network_directions_and_counter_resets() {
        const rates = Proc.networkRates({ rx: 1000, tx: 500 }, { rx: 3000, tx: 1500 }, 2);
        compare(rates.rx, 1000);
        compare(rates.tx, 500);
        compare(Proc.networkRates({ rx: 1000, tx: 500 }, { rx: 200, tx: 1000 }, 2).rx, 0);
        compare(Proc.networkRates(null, { rx: 3000, tx: 1500 }, 2).tx, 0);
        compare(Proc.networkRates({ rx: 0, tx: 0 }, { rx: 100, tx: 100 }, 0).rx, 0);
    }

    function test_history_capacity_follows_graph_window() {
        compare(Proc.historyCapacity(60, 1000), 60);
        compare(Proc.historyCapacity(10, 250), 40);
        compare(Proc.historyCapacity(300, 250), 600);
        compare(Proc.historyCapacity(300, 5000), 60);
        compare(Proc.historyCapacity(0, 1000), 60);
        compare(Proc.historyCapacity(60, 0), 60);
    }
}
