#include "../DesktopController.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QtTest>

class AccountActionsTest : public QObject {
    Q_OBJECT
private slots:
    void onlySupportedActionsReachTheTerminal() {
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        const QByteArray originalPath = qgetenv("PATH");
        qputenv("HOME", temporary.path().toUtf8());
        qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
        qputenv("PATH", temporary.path().toUtf8());
        const auto writeExecutable = [&](const QString &name, const QByteArray &content) {
            QFile file(temporary.filePath(name));
            if (!file.open(QIODevice::WriteOnly) || file.write(content) != content.size()) return false;
            return file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        };
        QVERIFY(writeExecutable("codex", "#!/bin/sh\nexit 0\n"));
        QVERIFY(writeExecutable("claude", "#!/bin/sh\nexit 0\n"));
        QVERIFY(writeExecutable("fake-cli", "#!/bin/sh\nprintf '[]'\n"));
        qputenv("ACCOUNT_TEST_LOG", temporary.filePath("arguments").toUtf8());
        // Make the create-before-write race deterministic, including on fast runners.
        QVERIFY(writeExecutable("xdg-terminal-exec",
            "#!/bin/sh\nexec > \"$ACCOUNT_TEST_LOG\"\n/bin/sleep 0.2\nprintf '%s\\n' \"$@\"\n"));
        DesktopController controller(temporary.filePath("fake-cli"));
        QVERIFY(!controller.accountAction("codex;anything", "login"));
        QVERIFY(!controller.accountAction("codex", "unrecognized"));
        QVERIFY(!QFile::exists(temporary.filePath("arguments")));
        // The shell's redirect creates the log before printf fills it, so wait for the contents,
        // not just the file.
        const auto logged = [&] {
            QFile file(temporary.filePath("arguments"));
            return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
        };
        QVERIFY(controller.accountAction("claude", "login"));
        QTRY_COMPARE(logged(), QByteArray("--hold\n--\n") + temporary.filePath("claude").toUtf8() + "\nauth\nlogin\n");
        QVERIFY(QFile::remove(temporary.filePath("arguments")));
        QVERIFY(controller.accountAction("codex", "logout"));
        QTRY_COMPARE(logged(), QByteArray("--hold\n--\n") + temporary.filePath("codex").toUtf8() + "\nlogout\n");
        qputenv("PATH", originalPath);
    }

    // A hub switch runs only through a prompt token, always with --confirm, and its pending state is
    // re-read with the --pending-* flags until the hub answers. Synthetic HOME and fake CLI only.
    void hubSwitchNeedsPromptConfirmAndResolvesPending() {
        QTemporaryDir temporary;
        QVERIFY(temporary.isValid());
        qputenv("HOME", temporary.path().toUtf8());
        qputenv("XDG_CONFIG_HOME", (temporary.path() + "/config").toUtf8());
        qputenv("HUB_TEST_ROOT", temporary.path().toUtf8());
        qputenv("CODEXBAR_HUB_PENDING_POLL_SECONDS", "1");
        const auto python = QStandardPaths::findExecutable("python3");
        QVERIFY(!python.isEmpty());
        QFile fake(temporary.filePath("fake-cli"));
        QVERIFY(fake.open(QIODevice::WriteOnly));
        fake.write("#!" + python.toUtf8() + R"PY(
import datetime, json, os, pathlib, sys
root = pathlib.Path(os.environ['HUB_TEST_ROOT'])
args = sys.argv[1:]
with (root / 'calls').open('a') as log: log.write(' '.join(args) + '\n')
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
provider = args[args.index('--provider') + 1] if '--provider' in args else ''
if args[:2] == ['hub', 'switch']:
    print(json.dumps({'schemaVersion': 1, 'provider': provider, 'outcome': 'requested', 'error': None,
        'request': {'requestId': 'r1', 'targetIdSuffix': '3c4d', 'targetEmail': 'h***3c4d@example.invalid',
                    'requestedAt': now}}))
elif args[:2] == ['hub', 'accounts'] and provider == 'codex':
    def account(suffix, active):
        return {'idSuffix': suffix, 'label': None, 'email': 'h***%s@example.invalid' % suffix, 'active': active,
            'paused': False, 'needsReauth': False, 'health': 'Healthy', 'quotaUnavailable': False,
            'nearLimit': False, 'canSwitch': not active, 'quotaSummary': [{'label': '5h', 'usedPercent': 30}],
            'usage': {'primary': {'usedPercent': 30, 'windowMinutes': 300}}}
    answer = {'schemaVersion': 1, 'provider': 'codex', 'configured': True, 'origin': 'snapshot', 'hub': 'office',
        'updatedAt': now, 'stale': False, 'switchable': True, 'switchReason': None, 'activeIdSuffix': '1a2b',
        'accounts': [account('1a2b', True), account('3c4d', False)], 'lastRequests': [], 'error': None}
    if '--pending-request-id' in args:
        state = root / 'resolution'
        answer['pending'] = {'requestId': args[args.index('--pending-request-id') + 1],
            'resolution': state.read_text().strip() if state.exists() else 'pending', 'code': 'busy', 'reason': None}
    print(json.dumps(answer))
elif args[:1] == ['hub']:
    print(json.dumps({'schemaVersion': 1, 'provider': provider, 'configured': False, 'accounts': [], 'error': None}))
else:
    print('[]')
)PY");
        fake.close();
        QVERIFY(fake.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        const auto calls = [&] {
            QFile file(temporary.filePath("calls"));
            return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
        };
        const auto codex = [](const DesktopController &controller) { return controller.hub().value("codex").toMap(); };
        DesktopController controller(temporary.filePath("fake-cli"));
        QTRY_VERIFY(codex(controller).value("hasPool").toBool());
        QTRY_COMPARE(controller.entries().value(0).toMap().value("source").toString(), QString("opencodex"));
        // The only selected provider is served by the hub, so native Codex usage is never fetched.
        QVERIFY(!calls().contains("usage"));
        QVERIFY(!controller.confirmHubSwitch("not-a-prompt"));
        QVERIFY(!controller.prepareHubSwitch("codex", 0).value("ok").toBool());
        auto prompt = controller.prepareHubSwitch("codex", 1);
        QVERIFY(prompt.value("ok").toBool());
        QCOMPARE(prompt.value("title").toString(), QString("Switch the opencodex hub to Account 2?"));
        QCOMPARE(prompt.value("paragraphs").toStringList().value(0),
            QString("Every machine that uses this hub moves to this account on its next request."));
        controller.cancelHubSwitch();
        QVERIFY(!controller.confirmHubSwitch(prompt.value("token").toString()));
        QVERIFY(!calls().contains("hub switch"));
        prompt = controller.prepareHubSwitch("codex", 1);
        QVERIFY(controller.confirmHubSwitch(prompt.value("token").toString()));
        // A second click while the first runs or is pending is ignored.
        QVERIFY(!controller.prepareHubSwitch("codex", 1).value("ok").toBool());
        QTRY_VERIFY(calls().contains(
            "hub switch --provider codex --id-suffix 3c4d --email h***3c4d@example.invalid --confirm --format json"));
        QTRY_COMPARE(codex(controller).value("notices").toStringList(), QStringList{"The hub is switching accounts…"});
        QTRY_VERIFY(calls().contains("--pending-request-id r1 --pending-target-id-suffix 3c4d "
            "--pending-target-email h***3c4d@example.invalid --pending-requested-at "));
        QCOMPARE(calls().count("hub switch"), 1);
        QFile resolution(temporary.filePath("resolution"));
        QVERIFY(resolution.open(QIODevice::WriteOnly) && resolution.write("refused") > 0);
        resolution.close();
        QTRY_COMPARE_WITH_TIMEOUT(codex(controller).value("notices").toStringList(),
            QStringList{"The hub refused the switch: busy"}, 8000);
        QVERIFY(QFile::remove(temporary.filePath("resolution")));
        prompt = controller.prepareHubSwitch("codex", 1);
        QVERIFY(controller.confirmHubSwitch(prompt.value("token").toString()));
        QTRY_COMPARE(calls().count("hub switch"), 2);
        QTRY_COMPARE(codex(controller).value("notices").toStringList(), QStringList{"The hub is switching accounts…"});
        QVERIFY(resolution.open(QIODevice::WriteOnly) && resolution.write("expired") > 0);
        resolution.close();
        QTRY_COMPARE_WITH_TIMEOUT(codex(controller).value("notices").toStringList(),
            QStringList{"The switch result is unknown. Refresh the hub before trying again."}, 8000);
        // The IPC snapshot keeps its schema and carries none of the list.
        const auto snapshot = QString::fromUtf8(QJsonDocument(controller.snapshot()).toJson());
        for (const auto &secret : {"example.invalid", "3c4d", "r1\"", "office", "switching"})
            QVERIFY2(!snapshot.contains(secret), secret);
        qunsetenv("CODEXBAR_HUB_PENDING_POLL_SECONDS");
    }
};

QTEST_GUILESS_MAIN(AccountActionsTest)
#include "tst_accounts.moc"
