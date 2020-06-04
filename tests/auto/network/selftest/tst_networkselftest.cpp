/****************************************************************************
**
** Copyright (C) 2020 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the test suite of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/


#include <QtTest/QtTest>

#include "../../network-settings.h"

class tst_NetworkSelftest : public QObject
{
    Q_OBJECT

private slots:
    void testServerIsAvailableInCI();
};

void tst_NetworkSelftest::testServerIsAvailableInCI()
{
    if (!qEnvironmentVariable("QTEST_ENVIRONMENT").split(' ').contains("ci"))
        QSKIP("Not running in the CI");

    if (qEnvironmentVariable("QT_QPA_PLATFORM").contains("offscreen")
          && !qEnvironmentVariableIsEmpty("QEMU_LD_PREFIX"))
        QSKIP("Not support yet for B2Qt");

#if !defined(QT_TEST_SERVER)
    QVERIFY2(QtNetworkSettings::verifyTestNetworkSettings(),
        "Test server must be available when running in the CI");
#endif
}

QTEST_MAIN(tst_NetworkSelftest)

#include "tst_networkselftest.moc"
